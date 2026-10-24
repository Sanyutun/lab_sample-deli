import 'package:shared_preferences/shared_preferences.dart';

/// Last successfully synced payloads, so the app can still show a delivery man
/// their own figures when the office server is unreachable. Read-only cache:
/// it never becomes a source of truth for money.
abstract class CacheStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> clear();
}

class PrefsCacheStore implements CacheStore {
  static const _prefix = 'companion.cache.';

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }
}

class MemoryCacheStore implements CacheStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> clear() async => _values.clear();
}
