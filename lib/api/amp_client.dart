import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class AmpException implements Exception {
  AmpException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AmpMethodUnavailable extends AmpException {
  AmpMethodUnavailable(this.module, this.method)
    : super(
        'API-Methode „$method“ nicht gefunden (Modul $module). '
        'Diese Funktion wird von dieser AMP-Installation nicht bereitgestellt.',
      );

  final String module;
  final String method;
}

/// Low-level client for the AMP JSON API.
///
/// All calls are `POST <baseUrl>/API/<Module>/<Method>` with a JSON body that
/// contains the parameters plus `SESSIONID`. Instances managed by the ADS are
/// reached through the ADS proxy: `/API/ADSModule/Servers/<id>/API/...`, each
/// with its own session.
class AmpClient {
  AmpClient({
    required String baseUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : baseUrl = normalizeUrl(baseUrl),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  String? _adsSession;
  final Map<String, String> _instanceSessions = {};
  Future<String>? _adsLogin;
  final Map<String, Future<String>> _instanceLogins = {};

  /// Track which API methods are supported by this AMP installation.
  /// Populated lazily when a "missing method" error is detected.
  final Set<String> supportedMethods = {};
  final Set<String> unsupportedMethods = {};

  String _methodKey(String module, String method, String? instanceId) =>
      '${instanceId ?? 'ADS'}:$module/$method';

  bool isMethodSupported(
    String method, {
    String module = 'Core',
    String? instanceId,
  }) {
    final key = _methodKey(module, method, instanceId);
    if (supportedMethods.contains(key)) return true;
    if (unsupportedMethods.contains(key)) return false;
    return true; // Assume supported until proven otherwise
  }

  void markMethodUnsupported(
    String method, {
    String module = 'Core',
    String? instanceId,
  }) {
    final key = _methodKey(module, method, instanceId);
    supportedMethods.remove(key);
    unsupportedMethods.add(key);
  }

  void markMethodSupported(
    String method, {
    String module = 'Core',
    String? instanceId,
  }) {
    final key = _methodKey(module, method, instanceId);
    supportedMethods.add(key);
    unsupportedMethods.remove(key);
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  void close() => _http.close();

  // ---------------------------------------------------------------------------
  // Transport

  Uri _uri(String module, String method, String? instanceId) {
    final prefix = instanceId == null
        ? ''
        : '/API/ADSModule/Servers/$instanceId';
    return Uri.parse('$baseUrl$prefix/API/$module/$method');
  }

  Future<dynamic> _post(
    String module,
    String method,
    Map<String, dynamic> params, {
    String? instanceId,
    String? session,
  }) async {
    final body = {...params, 'SESSIONID': ?session};
    final http.Response res;
    try {
      res = await _http
          .post(
            _uri(module, method, instanceId),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw AmpException('Zeitüberschreitung – Server nicht erreichbar.');
    } catch (e) {
      throw AmpException('Verbindung fehlgeschlagen: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw _Unauthorized();
    }
    if (res.body.isEmpty && res.statusCode == 200) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      if (res.statusCode != 200) {
        throw AmpException('HTTP ${res.statusCode} bei $module/$method');
      }
      throw AmpException('Ungültige Antwort vom Server (kein JSON).');
    }

    if (decoded is Map<String, dynamic>) {
      final title = decoded['Title']?.toString() ?? '';
      final message = decoded['Message']?.toString() ?? '';
      if (title.toLowerCase().contains('unauthori')) throw _Unauthorized();
      if (title.toLowerCase().contains('missingmethod') ||
          title.toLowerCase().contains('methodnotfound') ||
          RegExp(
            r'missing\s+method|method\b.*\bnot found',
            caseSensitive: false,
          ).hasMatch('$title $message')) {
        throw AmpMethodUnavailable(module, method);
      }
      if (decoded.containsKey('Title') &&
          (decoded.containsKey('StackTrace') ||
              decoded.containsKey('Message'))) {
        throw AmpException('$title: $message'.trim());
      }
      // Non-object return values are wrapped as {"result": ...}.
      if (decoded.length == 1 && decoded.containsKey('result')) {
        if (res.statusCode != 200) {
          throw AmpException('HTTP ${res.statusCode} bei $module/$method');
        }
        return decoded['result'];
      }
    }
    if (res.statusCode != 200) {
      throw AmpException('HTTP ${res.statusCode} bei $module/$method');
    }
    return decoded;
  }

  // ---------------------------------------------------------------------------
  // Authentication

  Future<String> _login({String? instanceId}) async {
    Future<Map<String, dynamic>?> attempt(String pw, String token) async {
      final r = await _post('Core', 'Login', {
        'username': username,
        'password': pw,
        'token': token,
        'rememberMe': false,
      }, instanceId: instanceId);
      return r is Map<String, dynamic> ? r : null;
    }

    var result = await attempt(password, '');
    // Instances behind the ADS also accept the ADS session as SSO token.
    if ((result?['success'] != true) && instanceId != null) {
      final ads = await _adsSessionId();
      result = await attempt('', ads);
    }

    if (result == null || result['success'] != true) {
      final reason = result?['resultReason']?.toString();
      throw AmpException(
        reason == null || reason.isEmpty
            ? 'Anmeldung fehlgeschlagen. Benutzer oder Passwort falsch?'
            : 'Anmeldung fehlgeschlagen: $reason',
      );
    }
    final sid = result['sessionID']?.toString();
    if (sid == null || sid.isEmpty) {
      throw AmpException('Anmeldung fehlgeschlagen: keine Session erhalten.');
    }
    return sid;
  }

  Future<String> _adsSessionId() async {
    if (_adsSession != null) return _adsSession!;
    final login = _adsLogin ??= _login();
    try {
      final sid = await login;
      if (identical(_adsLogin, login)) _adsSession = sid;
      return sid;
    } finally {
      if (identical(_adsLogin, login)) _adsLogin = null;
    }
  }

  Future<String> _instanceSessionId(String id) async {
    if (_instanceSessions.containsKey(id)) return _instanceSessions[id]!;
    final login = _instanceLogins.putIfAbsent(id, () => _login(instanceId: id));
    try {
      final sid = await login;
      if (identical(_instanceLogins[id], login)) _instanceSessions[id] = sid;
      return sid;
    } finally {
      if (identical(_instanceLogins[id], login)) _instanceLogins.remove(id);
    }
  }

  /// Performs an authenticated call, logging in again once if the session
  /// has expired.
  Future<dynamic> call(
    String module,
    String method, [
    Map<String, dynamic> params = const {},
    String? instanceId,
  ]) async {
    Future<String> session() =>
        instanceId == null ? _adsSessionId() : _instanceSessionId(instanceId);

    void invalidate() {
      if (instanceId == null) {
        _adsSession = null;
        _adsLogin = null;
        _instanceSessions.clear();
        _instanceLogins.clear();
      } else {
        _instanceSessions.remove(instanceId);
        _instanceLogins.remove(instanceId);
      }
    }

    try {
      Future<dynamic> send() async => _post(
        module,
        method,
        params,
        instanceId: instanceId,
        session: await session(),
      );
      dynamic result;
      try {
        result = await send();
      } on _Unauthorized {
        invalidate();
        try {
          result = await send();
        } on _Unauthorized {
          throw AmpException('Keine Berechtigung für $module/$method.');
        }
      }
      markMethodSupported(method, module: module, instanceId: instanceId);
      return result;
    } on AmpMethodUnavailable catch (e) {
      if (e.module == module && e.method == method) {
        markMethodUnsupported(method, module: module, instanceId: instanceId);
      }
      rethrow;
    }
  }

  /// Verifies URL and credentials. Returns the module info on success.
  Future<String> testConnection() async {
    final info = await _post('Core', 'GetModuleInfo', const {});
    if (info is! Map || info['Author'] != 'CubeCoders Limited') {
      throw AmpException('Unter dieser URL läuft kein AMP-Panel.');
    }
    _adsSession = null;
    _adsLogin = null;
    await _adsSessionId();
    return info['AppName']?.toString() ?? 'AMP';
  }

  Future<void> logout() async {
    final sid = _adsSession;
    _adsSession = null;
    _adsLogin = null;
    _instanceSessions.clear();
    _instanceLogins.clear();
    supportedMethods.clear();
    unsupportedMethods.clear();
    if (sid != null) {
      try {
        await _post('Core', 'Logout', const {}, session: sid);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // ADS (controller)

  Future<List<AmpInstance>> getInstances() async {
    final r = await call('ADSModule', 'GetInstances');
    return _readResponse('ADSModule/GetInstances', r, (value) {
      final instances = <AmpInstance>[];
      for (final target in _list(value)) {
        final targetMap = _map(target);
        if (!targetMap.containsKey('AvailableInstances')) {
          throw const FormatException();
        }
        final available = targetMap['AvailableInstances'];
        if (available == null) {
          continue; // An offline ADS target has no instances.
        }
        for (final i in _list(available)) {
          final data = _map(i);
          _requiredString(data, 'InstanceID');
          final inst = AmpInstance.fromJson(data);
          // Skip the ADS itself.
          if (inst.module == 'ADS') continue;
          instances.add(inst);
        }
      }
      instances.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return instances;
    });
  }

  /// Starts the AMP instance process itself (not the game server).
  Future<void> startInstanceProcess(AmpInstance i) async {
    await _action('ADSModule', 'StartInstance', {
      'InstanceName': i.instanceName,
    });
    _instanceSessions.remove(i.id);
    _instanceLogins.remove(i.id);
  }

  /// Stops the AMP instance process itself via the ADS controller.
  Future<void> stopInstanceProcess(AmpInstance i) async {
    await _action('ADSModule', 'StopInstance', {
      'InstanceName': i.instanceName,
    });
    _instanceSessions.remove(i.id);
    _instanceLogins.remove(i.id);
  }

  // ---------------------------------------------------------------------------
  // Instance (game server)

  Future<InstanceStatus> getStatus(String instanceId) async {
    final r = await call('Core', 'GetStatus', const {}, instanceId);
    return _readResponse('Core/GetStatus', r, _status);
  }

  Future<void> startServer(String id) => _action('Core', 'Start', {}, id);
  Future<void> stopServer(String id) => _action('Core', 'Stop', {}, id);
  Future<void> restartServer(String id) => _action('Core', 'Restart', {}, id);
  Future<void> killServer(String id) => _action('Core', 'Kill', {}, id);

  Future<void> sendConsole(String id, String message) =>
      call('Core', 'SendConsoleMessage', {'message': message}, id);

  /// Status plus console lines since the last call (per session).
  Future<InstanceUpdates> getUpdates(String id) async {
    final r = await call('Core', 'GetUpdates', const {}, id);
    return _readResponse('Core/GetUpdates', r, (value) {
      final data = _map(value);
      if (!data.containsKey('Status') && !data.containsKey('ConsoleEntries')) {
        throw const FormatException();
      }
      if (data['Status'] != null) _status(data['Status']);
      if (data['ConsoleEntries'] != null) _list(data['ConsoleEntries']);
      return InstanceUpdates.fromJson(data);
    });
  }

  Future<List<String>> getUsers(String id) async {
    final r = await call('Core', 'GetUserList', const {}, id);
    return _readResponse('Core/GetUserList', r, (value) {
      final users = value is Map ? value.values.toList() : _list(value);
      if (users.any((user) => user is! String)) throw const FormatException();
      return users.cast<String>().toList()..sort();
    });
  }

  Future<List<BackupEntry>> getBackups(String id) async {
    final r = await call('LocalFileBackupPlugin', 'GetBackups', const {}, id);
    return _readResponse('LocalFileBackupPlugin/GetBackups', r, (value) {
      final values = value is Map && value.containsKey('Backups')
          ? value['Backups']
          : value;
      return _list(values).map((entry) {
        final data = _map(entry);
        _requiredString(data, 'Id');
        return BackupEntry.fromJson(data);
      }).toList();
    });
  }

  Future<void> createBackup(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-Name darf nicht leer sein.');
    }
    return _action('LocalFileBackupPlugin', 'TakeBackup', {
      'Title': clean,
      'Description': '',
      'Sticky': false,
    }, id);
  }

  Future<void> restoreBackup(String id, String backupId) {
    final clean = backupId.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-ID darf nicht leer sein.');
    }
    return _action('LocalFileBackupPlugin', 'RestoreBackup', {
      'BackupId': clean,
    }, id);
  }

  Future<void> deleteBackup(String id, String backupId) {
    final clean = backupId.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-ID darf nicht leer sein.');
    }
    return _action('LocalFileBackupPlugin', 'DeleteLocalBackup', {
      'BackupId': clean,
    }, id);
  }

  // File management
  Future<List<FileEntry>> getFiles(String id, {String directory = ''}) async {
    final r = await call('FileManagerPlugin', 'GetDirectoryListing', {
      'Dir': directory,
    }, id);
    return _readResponse('FileManagerPlugin/GetDirectoryListing', r, (value) {
      return _list(value).map((entry) {
        final data = _map(entry);
        final filename = _requiredString(data, 'Filename');
        return FileEntry.fromJson({
          ...data,
          'Path': directory.isEmpty
              ? filename
              : '${directory.replaceAll(RegExp(r'/+$'), '')}/$filename',
        });
      }).toList();
    });
  }

  Future<void> createDirectory(String id, String path) {
    final clean = path.trim();
    if (clean.isEmpty) {
      throw AmpException('Pfad darf nicht leer sein.');
    }
    return _action('FileManagerPlugin', 'CreateDirectory', {
      'NewPath': clean,
    }, id);
  }

  Future<void> deleteFile(String id, String path, {bool isDirectory = false}) {
    final clean = path.trim();
    if (clean.isEmpty) {
      throw AmpException('Pfad darf nicht leer sein.');
    }
    return _action(
      'FileManagerPlugin',
      isDirectory ? 'TrashDirectory' : 'TrashFile',
      {isDirectory ? 'DirectoryName' : 'Filename': clean},
      id,
    );
  }

  Future<void> renameFile(
    String id,
    String oldPath,
    String newName, {
    bool isDirectory = false,
  }) {
    final cleanOld = oldPath.trim();
    final cleanNew = newName.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty) {
      throw AmpException('Umbenennen benötigt gültige Dateinamen.');
    }
    return _action(
      'FileManagerPlugin',
      isDirectory ? 'RenameDirectory' : 'RenameFile',
      {
        isDirectory ? 'oldDirectory' : 'Filename': cleanOld,
        isDirectory ? 'NewDirectoryName' : 'NewFilename': cleanNew,
      },
      id,
    );
  }

  Future<List<SettingEntry>> getSettings(String id) async {
    final r = await call('Core', 'GetSettingsSpec', const {}, id);
    return _readResponse('Core/GetSettingsSpec', r, (value) {
      final values = <SettingEntry>[];
      for (final category in _map(value).values) {
        for (final entry in _list(category)) {
          final data = _map(entry);
          _requiredString(data, 'Node');
          values.add(SettingEntry.fromJson(data));
        }
      }
      values.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return values;
    });
  }

  Future<void> setSetting(String id, String name, String value) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw AmpException('Setting-Name darf nicht leer sein.');
    }
    return _action('Core', 'SetConfig', {
      'node': cleanName,
      'value': value,
    }, id);
  }

  Future<List<SchedulerTask>> getTasks(String id) async {
    final r = await call('Core', 'GetScheduleData', const {}, id);
    return _readResponse('Core/GetScheduleData', r, (value) {
      final triggers = _list(_map(value)['PopulatedTriggers']);
      final values = triggers.map((entry) {
        final data = _map(entry);
        _requiredString(data, 'Id');
        return SchedulerTask.fromJson(data);
      }).toList();
      values.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return values;
    });
  }

  Future<void> setTaskEnabled(String id, String taskId, bool enabled) {
    final cleanId = taskId.trim();
    if (cleanId.isEmpty) {
      throw AmpException('Task-ID darf nicht leer sein.');
    }
    return _action('Core', 'SetTriggerEnabled', {
      'Id': cleanId,
      'Enabled': enabled,
    }, id);
  }

  Future<List<AmpEvent>> getEvents(String id) async {
    final r = await call('Core', 'GetAuditLogEntries', {
      'Before': null,
      'Count': 100,
    }, id);
    return _readResponse('Core/GetAuditLogEntries', r, (value) {
      final values = _list(value)
          .map((entry) => AmpEvent.fromJson(_map(entry)))
          .toList();
      values.sort(
        (a, b) =>
            (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)),
      );
      return values;
    });
  }

  /// Application update progress is reflected in Core/GetStatus's State.
  /// Core/GetUpdateInfo describes AMP updates, not game server updates.
  Future<InstanceStatus> getUpdateStatus(String id) => getStatus(id);

  Future<void> runUpdate(String id) {
    return _action('Core', 'UpdateApplication', const {}, id);
  }

  T _readResponse<T>(String method, dynamic value, T Function(dynamic) parse) {
    if (value == false || (value is Map && value['Status'] == false)) {
      final reason = value is Map ? value['Reason']?.toString() : null;
      throw AmpException(reason ?? 'Abruf von $method fehlgeschlagen.');
    }
    try {
      return parse(value);
    } on FormatException {
      throw AmpException('Ungültige Antwort bei $method.');
    } on TypeError {
      throw AmpException('Ungültige Antwort bei $method.');
    } on RangeError {
      throw AmpException('Ungültige Antwort bei $method.');
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) throw const FormatException();
    return Map<String, dynamic>.from(value);
  }

  InstanceStatus _status(dynamic value) {
    final data = _map(value);
    if (int.tryParse('${data['State']}') == null) throw const FormatException();
    return InstanceStatus.fromJson(data);
  }

  List<dynamic> _list(dynamic value) {
    if (value is! List) throw const FormatException();
    return value;
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final field = value[key];
    if (field is! String || field.isEmpty) throw const FormatException();
    return field;
  }

  Future<void> _action(
    String module,
    String method, [
    Map<String, dynamic> params = const {},
    String? instanceId,
  ]) async {
    final r = await call(module, method, params, instanceId);
    if (r == false || (r is Map && r['Status'] == false)) {
      final reason = r is Map ? r['Reason']?.toString() : null;
      throw AmpException(
        reason == null || reason.isEmpty ? '$method fehlgeschlagen.' : reason,
      );
    }
  }
}

class _Unauthorized implements Exception {}
