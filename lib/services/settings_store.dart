import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerSettings {
  const ServerSettings({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;

  bool get isComplete =>
      url.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

/// Persists the connection settings in the platform keystore
/// (Android Keystore / iOS Keychain).
class SettingsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kUrl = 'server_url';
  static const _kUser = 'username';
  static const _kPass = 'password';

  Future<ServerSettings> load() async {
    final values = await _storage.readAll();
    return ServerSettings(
      url: values[_kUrl] ?? '',
      username: values[_kUser] ?? '',
      password: values[_kPass] ?? '',
    );
  }

  Future<void> save(ServerSettings s) async {
    await _storage.write(key: _kUrl, value: s.url);
    await _storage.write(key: _kUser, value: s.username);
    await _storage.write(key: _kPass, value: s.password);
  }

  Future<void> clear() => _storage.deleteAll();
}
