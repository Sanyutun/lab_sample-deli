import '../storage/app_storage.dart';

/// Small key-value settings store (commission_settings table).
class SettingsRepository {
  SettingsRepository(this._storage);
  final AppStorage _storage;

  /// Reconciliation detailed results flag rows whose commission was entered
  /// more than this many hours after the receipt time.
  static const String reconTimeGapHoursKey = 'recon.timeGapHours';
  static const double defaultReconTimeGapHours = 6;

  static const String _table = 'commission_settings';

  Future<void> set(String key, String value) async {
    final existing = await _storage.findOne(_table, {'key': key});
    if (existing == null) {
      await _storage.insert(_table, {'key': key, 'value': value});
    } else {
      await _storage.update(_table, {'key': key}, {'value': value});
    }
  }

  Future<String?> get(String key) async {
    final row = await _storage.findOne(_table, {'key': key});
    return row?['value'] as String?;
  }

  Future<Map<String, String>> all() async {
    final rows = await _storage.find(_table);
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }
}
