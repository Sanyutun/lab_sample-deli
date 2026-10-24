import '../../data/models/models.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../ids.dart';

/// GPS history policy for the office app.
///
/// Raw fixes are kept for [retentionMs] only; what matters for a delivered
/// receipt is copied into `delivery_trip_points` at the moment staff record the
/// delivery, and that copy is kept. A route is evidence of where the phone was,
/// never proof that a test was performed.
class TripService {
  TripService({
    required this.locations,
    required this.trips,
    required this.commissions,
  });

  final LocationRepository locations;
  final TripRepository trips;
  final CommissionRepository commissions;

  /// How long raw fixes and a preserved route both cover.
  static const Duration retention = Duration(minutes: 20);

  /// Copies [deliveryManId]'s fixes from the [retention] window before
  /// [verifiedAtMs] onto the commission. Called once per delivery, when the
  /// record is created; a second call for the same commission is a no-op.
  ///
  /// Returns the number of points preserved.
  Future<int> preserveForDelivery({
    required String barcode,
    required String commissionId,
    required String deliveryManId,
    required int verifiedAtMs,
  }) async {
    if (await trips.hasForCommission(commissionId)) return 0;
    final window = retention.inMilliseconds;
    final fixes = await locations.forDeliveryManBetween(
      deliveryManId,
      fromMs: verifiedAtMs - window,
      toMs: verifiedAtMs,
    );
    if (fixes.isEmpty) return 0;
    final now = nowMs();
    await trips.insertMany([
      for (final fix in fixes)
        _copy(fix, barcode: barcode, commissionId: commissionId, now: now),
    ]);
    return fixes.length;
  }

  /// Attaches a fix that reached the office *after* the delivery was recorded
  /// (the phone was offline at the till). Without this the receipt's route
  /// would keep a hole that the backlog later filled in.
  ///
  /// A fix belongs to a commission when it was captured no later than the
  /// delivery and no more than [retention] before it. Returns how many routes
  /// gained the point.
  Future<int> attachLateFix(DeliveryLocation fix) async {
    final window = retention.inMilliseconds;
    final records = await commissions.all(deliveryManId: fix.deliveryManId);
    var attached = 0;
    for (final record in records) {
      if (!record.isActive) continue;
      if (record.dateTime < fix.capturedAt) continue;
      if (record.dateTime - fix.capturedAt > window) continue;
      if (await trips.hasSource(record.id, fix.id)) continue;
      await trips.insertMany([
        _copy(
          fix,
          barcode: record.barcode,
          commissionId: record.id,
          now: nowMs(),
        ),
      ]);
      attached++;
    }
    return attached;
  }

  DeliveryTripPoint _copy(
    DeliveryLocation fix, {
    required String barcode,
    required String commissionId,
    required int now,
  }) => DeliveryTripPoint(
    id: newId('trip'),
    barcode: barcode.trim(),
    commissionId: commissionId,
    deliveryManId: fix.deliveryManId,
    latitude: fix.latitude,
    longitude: fix.longitude,
    accuracyM: fix.accuracyM,
    capturedAt: fix.capturedAt,
    createdAt: now,
    sourceId: fix.id,
  );

  /// The preserved route of a receipt, oldest fix first.
  Future<List<DeliveryTripPoint>> routeForBarcode(String barcode) =>
      trips.forBarcode(barcode);

  /// Every preserved point of one delivery man, oldest fix first.
  Future<List<DeliveryTripPoint>> routePointsFor(String deliveryManId) =>
      trips.forDeliveryMan(deliveryManId);

  /// Deletes raw fixes the office received longer than [retention] ago.
  /// Routes already preserved are copies, so they are unaffected.
  Future<int> purgeOldRawFixes({int? now}) {
    final cutoff = (now ?? nowMs()) - retention.inMilliseconds;
    return locations.purgeReceivedBefore(cutoff);
  }
}
