import '../models/models.dart';
import '../storage/app_storage.dart';

/// Today's action PIN per user. One row per user, replaced when the day rolls.
class DailyPinRepository {
  DailyPinRepository(this._storage);
  final AppStorage _storage;

  static const String table = 'daily_pins';

  Future<void> save(DailyPin pin) async {
    final row = pin.toMap();
    final existing = await _storage.findOne(table, {'user_id': pin.userId});
    if (existing == null) {
      try {
        await _storage.insert(table, row);
      } catch (_) {
        // Two office terminals may race on the first run of the day.
        await _storage.update(table, {'user_id': pin.userId}, row);
      }
    } else {
      await _storage.update(table, {'user_id': pin.userId}, row);
    }
  }

  Future<List<DailyPin>> all() async =>
      (await _storage.find(table)).map(DailyPin.fromMap).toList();
}
