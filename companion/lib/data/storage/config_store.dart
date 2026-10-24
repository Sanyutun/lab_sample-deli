import 'package:shared_preferences/shared_preferences.dart';

/// Persists the office server address. The address is not a secret, so plain
/// preferences are fine; the session token lives in [SessionStore] instead.
abstract class ConfigStore {
  Future<String?> readServerUrl();
  Future<void> writeServerUrl(String url);
}

class PrefsConfigStore implements ConfigStore {
  static const _key = 'companion.server.url';

  @override
  Future<String?> readServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> writeServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, url);
  }
}

class MemoryConfigStore implements ConfigStore {
  String? _url;

  @override
  Future<String?> readServerUrl() async => _url;

  @override
  Future<void> writeServerUrl(String url) async => _url = url;
}
