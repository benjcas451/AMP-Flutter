import 'package:flutter/foundation.dart';

import '../api/amp_client.dart';
import '../services/settings_store.dart';

/// Holds the saved settings and the API client built from them.
class AppModel extends ChangeNotifier {
  AppModel(this._store);

  final SettingsStore _store;

  bool _loaded = false;
  ServerSettings _settings = const ServerSettings(
    url: '',
    username: '',
    password: '',
  );
  AmpClient? _client;

  bool get loaded => _loaded;
  ServerSettings get settings => _settings;
  bool get isConfigured => _settings.isComplete;

  AmpClient? get clientOrNull => _client;

  AmpClient get client {
    final c = _client;
    if (c == null) throw StateError('Keine Serververbindung konfiguriert.');
    return c;
  }

  Future<void> init() async {
    _settings = await _store.load();
    _rebuildClient();
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveSettings(ServerSettings s) async {
    final normalized = ServerSettings(
      url: AmpClient.normalizeUrl(s.url),
      username: s.username.trim(),
      password: s.password,
    );
    await _store.save(normalized);
    await _client?.logout();
    _settings = normalized;
    _rebuildClient();
    notifyListeners();
  }

  Future<void> clearSettings() async {
    await _client?.logout();
    await _store.clear();
    _settings = const ServerSettings(url: '', username: '', password: '');
    _rebuildClient();
    notifyListeners();
  }

  void _rebuildClient() {
    _client?.close();
    _client = _settings.isComplete
        ? AmpClient(
            baseUrl: _settings.url,
            username: _settings.username,
            password: _settings.password,
          )
        : null;
  }
}
