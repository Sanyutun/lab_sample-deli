import '../models/models.dart';
import '../storage/app_storage.dart';

/// Routes preserved for delivered receipts. Unlike raw fixes these are kept,
/// so the map for a receipt still works weeks later.
class TripRepository {
  TripRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'delivery_trip_points';

  Future<void> insertMany(List<DeliveryTripPoint> points) async {
    if (points.isEmpty) return;
    await _storage.insertMany(_table, [for (final p in points) p.toMap()]);
  }

  /// Oldest first — the order the man actually travelled.
  Future<List<DeliveryTripPoint>> forBarcode(String barcode) async {
    final rows = await _storage.find(
      _table,
      where: {'barcode': barcode.trim()},
      orderBy: 'captured_at',
    );
    return rows.map(DeliveryTripPoint.fromMap).toList();
  }

  /// Every preserved point for one delivery man, oldest first — his whole
  /// history, so the caller can group it into routes however it likes.
  Future<List<DeliveryTripPoint>> forDeliveryMan(String deliveryManId) async {
    final rows = await _storage.find(
      _table,
      where: {'delivery_man_id': deliveryManId},
      orderBy: 'captured_at',
    );
    return rows.map(DeliveryTripPoint.fromMap).toList();
  }

  Future<bool> hasForCommission(String commissionId) async {
    final row = await _storage.findOne(_table, {'commission_id': commissionId});
    return row != null;
  }

  /// Whether a point copied from raw fix [sourceId] is already on this
  /// commission's route.
  Future<bool> hasSource(String commissionId, String sourceId) async {
    final row = await _storage.findOne(_table, {
      'commission_id': commissionId,
      'source_id': sourceId,
    });
    return row != null;
  }
}
