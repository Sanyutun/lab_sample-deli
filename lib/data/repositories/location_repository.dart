import '../models/models.dart';
import '../storage/app_storage.dart';

/// GPS fixes captured by companion apps.
///
/// Raw fixes are short-lived: [purgeReceivedBefore] drops everything that was
/// received before a cutoff, because anything worth keeping for a delivered
/// receipt was already copied into `delivery_trip_points`.
class LocationRepository {
  LocationRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'delivery_locations';

  Future<void> insert(DeliveryLocation location) async {
    await _storage.insert(_table, location.toMap());
  }

  Future<List<DeliveryLocation>> forDeliveryMan(
    String deliveryManId, {
    int limit = 100,
  }) async {
    final rows = await _storage.find(
      _table,
      where: {'delivery_man_id': deliveryManId},
      orderBy: '-captured_at',
    );
    return rows.take(limit).map(DeliveryLocation.fromMap).toList();
  }

  /// Fixes captured in [fromMs, toMs], oldest first. Times come from the phone,
  /// so this is what "the 20 minutes before the delivery" is measured on.
  Future<List<DeliveryLocation>> forDeliveryManBetween(
    String deliveryManId, {
    required int fromMs,
    required int toMs,
  }) async {
    final rows = await _storage.find(
      _table,
      where: {'delivery_man_id': deliveryManId},
      orderBy: 'captured_at',
    );
    return [
      for (final row in rows.map(DeliveryLocation.fromMap))
        if (row.capturedAt >= fromMs && row.capturedAt <= toMs) row,
    ];
  }

  /// Drops fixes the office received before [cutoffMs]. Returns how many rows
  /// went, for logging and tests.
  Future<int> purgeReceivedBefore(int cutoffMs) async {
    final rows = await _storage.find(_table);
    var removed = 0;
    for (final row in rows) {
      final received = (row['received_at'] as num?)?.toInt() ?? 0;
      if (received != 0 && received < cutoffMs) {
        await _storage.remove(_table, {'id': row['id']});
        removed++;
      }
    }
    return removed;
  }

  /// The fix with this phone-assigned id, if the phone already sent it. Used to
  /// make a repeated upload a no-op instead of a duplicate.
  Future<DeliveryLocation?> findByClientId(
    String deliveryManId,
    String clientId,
  ) async {
    final row = await _storage.findOne(_table, {
      'delivery_man_id': deliveryManId,
      'client_id': clientId,
    });
    return row == null ? null : DeliveryLocation.fromMap(row);
  }
}
