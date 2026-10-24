import 'package:shared_preferences/shared_preferences.dart';

import '../services/delivery_watch.dart';

/// Plain preferences backing for the new-delivery watch. The values are only
/// board position numbers, so they are not secrets and do not belong in secure
/// storage.
class PrefsSeenStore implements SeenKvStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('companion.$key');
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('companion.$key', value);
  }
}

class MemorySeenStore implements SeenKvStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
