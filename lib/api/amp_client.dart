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

  /// Track which API methods are supported by this AMP installation.
  /// Populated lazily when a "missing method" error is detected.
  final Set<String> supportedMethods = {};
  final Set<String> unsupportedMethods = {};

  bool isMethodSupported(String method) {
    if (supportedMethods.contains(method)) return true;
    if (unsupportedMethods.contains(method)) return false;
    return true; // Assume supported until proven otherwise
  }

  void markMethodUnsupported(String method) {
    unsupportedMethods.add(method);
  }

  void markMethodSupported(String method) {
    supportedMethods.add(method);
    unsupportedMethods.remove(method);
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
    if (res.statusCode != 200) {
      throw AmpException('HTTP ${res.statusCode} bei $module/$method');
    }
    if (res.body.isEmpty) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw AmpException('Ungültige Antwort vom Server (kein JSON).');
    }

    if (decoded is Map<String, dynamic>) {
      // AMP reports errors as {"Title": ..., "Message": ..., "StackTrace": ...}.
      if (decoded.containsKey('Title') && decoded.containsKey('StackTrace')) {
        final title = decoded['Title']?.toString() ?? '';
        if (title.toLowerCase().contains('unauthori')) throw _Unauthorized();
        final msg = decoded['Message']?.toString() ?? '';
        throw AmpException('$title: $msg'.trim());
      }
      // Some AMP installations report "missing method" as a structured error
      // without a StackTrace but with a specific message.
      final title = decoded['Title']?.toString() ?? '';
      final message = decoded['Message']?.toString() ?? '';
      if (title.toLowerCase().contains('missing') ||
          message.toLowerCase().contains('missing method')) {
        throw AmpException(
          'API-Methode „$method" nicht gefunden (Modul $module). '
          'Diese Funktion wird von dieser AMP-Installation nicht bereitgestellt.',
        );
      }
      // Non-object return values are wrapped as {"result": ...}.
      if (decoded.length == 1 && decoded.containsKey('result')) {
        return decoded['result'];
      }
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

  Future<String> _adsSessionId() async => _adsSession ??= await _login();

  Future<String> _instanceSessionId(String id) async =>
      _instanceSessions[id] ??= await _login(instanceId: id);

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
        _instanceSessions.clear();
      } else {
        _instanceSessions.remove(instanceId);
      }
    }

    try {
      final result = await _post(
        module,
        method,
        params,
        instanceId: instanceId,
        session: await session(),
      );
      markMethodSupported(method);
      return result;
    } on AmpException catch (e) {
      if (e.message.toLowerCase().contains('missing') ||
          e.message.toLowerCase().contains('nicht gefunden')) {
        markMethodUnsupported(method);
      }
      rethrow;
    } on _Unauthorized {
      invalidate();
      try {
        return await _post(
          module,
          method,
          params,
          instanceId: instanceId,
          session: await session(),
        );
      } on _Unauthorized {
        throw AmpException('Keine Berechtigung für $module/$method.');
      }
    }
  }

  /// Verifies URL and credentials. Returns the module info on success.
  Future<String> testConnection() async {
    final info = await _post('Core', 'GetModuleInfo', const {});
    if (info is! Map || info['Author'] != 'CubeCoders Limited') {
      throw AmpException('Unter dieser URL läuft kein AMP-Panel.');
    }
    _adsSession = null;
    await _adsSessionId();
    return info['AppName']?.toString() ?? 'AMP';
  }

  Future<void> logout() async {
    final sid = _adsSession;
    _adsSession = null;
    _instanceSessions.clear();
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
    if (r is! List) return const [];
    final instances = <AmpInstance>[];
    for (final target in r) {
      final available = (target as Map)['AvailableInstances'];
      if (available is! List) continue;
      for (final i in available) {
        final inst = AmpInstance.fromJson(Map<String, dynamic>.from(i as Map));
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
  }

  /// Starts the AMP instance process itself (not the game server).
  Future<void> startInstanceProcess(AmpInstance i) async {
    await _action('ADSModule', 'StartInstance', {
      'InstanceName': i.instanceName,
    });
    _instanceSessions.remove(i.id);
  }

  /// Stops the AMP instance process itself via the ADS controller.
  Future<void> stopInstanceProcess(AmpInstance i) async {
    await _action('ADSModule', 'StopInstance', {
      'InstanceName': i.instanceName,
    });
    _instanceSessions.remove(i.id);
  }

  // ---------------------------------------------------------------------------
  // Instance (game server)

  Future<InstanceStatus> getStatus(String instanceId) async {
    final r = await call('Core', 'GetStatus', const {}, instanceId);
    if (r is! Map) throw AmpException('Status nicht verfügbar.');
    return InstanceStatus.fromJson(Map<String, dynamic>.from(r));
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
    if (r is! Map) throw AmpException('Keine Daten von der Instanz.');
    return InstanceUpdates.fromJson(Map<String, dynamic>.from(r));
  }

  Future<List<String>> getUsers(String id) async {
    final r = await call('Core', 'GetUserList', const {}, id);
    if (r is Map) return r.values.map((v) => v.toString()).toList()..sort();
    if (r is List) return r.map((v) => v.toString()).toList()..sort();
    return const [];
  }

  Future<List<BackupEntry>> getBackups(String id) async {
    final r = await call('Core', 'GetBackups', const {}, id);
    final values = r is Map && r['Backups'] is List
        ? r['Backups'] as List
        : r is List
        ? r
        : const <dynamic>[];
    return values
        .map(
          (entry) =>
              BackupEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
  }

  Future<void> createBackup(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-Name darf nicht leer sein.');
    }
    return _action('Core', 'CreateBackup', {'BackupName': clean}, id);
  }

  Future<void> restoreBackup(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-Name darf nicht leer sein.');
    }
    return _action('Core', 'RestoreBackup', {'BackupName': clean}, id);
  }

  Future<void> deleteBackup(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw AmpException('Backup-Name darf nicht leer sein.');
    }
    return _action('Core', 'DeleteBackup', {'BackupName': clean}, id);
  }

  // File management
  Future<List<FileEntry>> getFiles(String id) async {
    final r = await call('Core', 'GetFiles', const {}, id);
    final values = r is Map && r['Files'] is List
        ? r['Files'] as List
        : r is List
        ? r
        : const <dynamic>[];
    return values
        .map(
          (entry) =>
              FileEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
  }

  Future<void> createDirectory(String id, String path) {
    final clean = path.trim();
    if (clean.isEmpty) {
      throw AmpException('Pfad darf nicht leer sein.');
    }
    return _action('Core', 'CreateDirectory', {'Path': clean}, id);
  }

  Future<void> deleteFile(String id, String path) {
    final clean = path.trim();
    if (clean.isEmpty) {
      throw AmpException('Pfad darf nicht leer sein.');
    }
    return _action('Core', 'DeleteFile', {'Path': clean}, id);
  }

  Future<void> renameFile(String id, String oldPath, String newName) {
    final cleanOld = oldPath.trim();
    final cleanNew = newName.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty) {
      throw AmpException('Umbenennen benötigt gültige Dateinamen.');
    }
    return _action('Core', 'RenameFile', {
      'OldPath': cleanOld,
      'NewName': cleanNew,
    }, id);
  }

  Future<List<SettingEntry>> getSettings(String id) async {
    final r = await call('Core', 'GetSettings', const {}, id);
    if (r is! Map) return const [];
    final values = r.values
        .whereType<Map>()
        .map((e) => SettingEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    values.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values;
  }

  Future<void> setSetting(String id, String name, String value) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw AmpException('Setting-Name darf nicht leer sein.');
    }
    return _action('Core', 'SetSetting', {
      'SettingName': cleanName,
      'Value': value.trim(),
    }, id);
  }

  Future<List<SchedulerTask>> getTasks(String id) async {
    final r = await call('Core', 'GetTasks', const {}, id);
    if (r is! Map) return const [];
    final values = r.values
        .whereType<Map>()
        .map((e) => SchedulerTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    values.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values;
  }

  Future<void> setTaskEnabled(String id, String taskId, bool enabled) {
    final cleanId = taskId.trim();
    if (cleanId.isEmpty) {
      throw AmpException('Task-ID darf nicht leer sein.');
    }
    return _action('Core', 'SetTaskEnabled', {
      'TaskID': cleanId,
      'Enabled': enabled,
    }, id);
  }

  Future<List<AmpEvent>> getEvents(String id) async {
    final r = await call('Core', 'GetEventLog', const {}, id);
    if (r is! Map) return const [];
    final values = r.values
        .whereType<Map>()
        .map((e) => AmpEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    values.sort(
      (a, b) => b.timestamp?.compareTo(a.timestamp ?? DateTime(0)) ?? 0,
    );
    return values;
  }

  Future<Map<String, dynamic>> getUpdateStatus(String id) async {
    final r = await call('Core', 'GetUpdateStatus', const {}, id);
    if (r is Map) return Map<String, dynamic>.from(r);
    return const {};
  }

  Future<void> runUpdate(String id) {
    return _action('Core', 'RunUpdate', const {}, id);
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
