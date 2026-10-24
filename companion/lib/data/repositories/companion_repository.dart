import 'dart:convert';

import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/failure.dart';
import '../api/companion_api.dart';
import '../storage/cache_store.dart';

/// A value plus whether it came from the cache because the server was
/// unreachable. Screens show a clear "offline" note when [stale] is true.
class SyncResult<T> {
  const SyncResult({required this.value, required this.stale, this.cachedAt});

  final T value;
  final bool stale;
  final DateTime? cachedAt;
}

/// Read-only companion data. Every figure is fetched from the office server;
/// on a network failure the last synced copy is shown rather than a guess.
class CompanionRepository {
  CompanionRepository({required this.api, required this.cache});

  final CompanionApi api;
  final CacheStore cache;

  Future<SyncResult<DeliveryManProfileDto>> profile() => _cached(
    'profile',
    () => api.me(),
    (v) => v.toJson(),
    DeliveryManProfileDto.fromJson,
  );

  Future<SyncResult<SummaryDto>> summary() => _cached(
    'summary',
    () => api.summary(),
    (v) => v.toJson(),
    SummaryDto.fromJson,
  );

  Future<SyncResult<List<CommissionDto>>> commissions({
    String? from,
    String? to,
    String? status,
  }) {
    final key = 'commissions.${from ?? ''}.${to ?? ''}.${status ?? 'all'}';
    return _cached(
      key,
      () => api.commissions(from: from, to: to, status: status),
      (v) => {
        'items': [for (final c in v) c.toJson()],
      },
      (json) => [
        for (final item in (json['items'] as List? ?? const []))
          CommissionDto.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Future<SyncResult<CommissionDto>> commission(String id) => _cached(
    'commission.$id',
    () => api.commission(id),
    (v) => v.toJson(),
    CommissionDto.fromJson,
  );

  Future<SyncResult<List<RewardDto>>> rewards() => _cached(
    'rewards',
    () => api.rewards(),
    (v) => {
      'items': [for (final r in v) r.toJson()],
    },
    (json) => [
      for (final item in (json['items'] as List? ?? const []))
        RewardDto.fromJson(item as Map<String, dynamic>),
    ],
  );

  Future<SyncResult<DeliveryBoardDto>> deliveryBoard() => _cached(
    'deliveryBoard',
    () => api.deliveryBoard(),
    (v) => v.toJson(),
    DeliveryBoardDto.fromJson,
  );

  Future<SyncResult<QrIdentityDto>> qr() =>
      _cached('qr', () => api.qr(), (v) => v.toJson(), QrIdentityDto.fromJson);

  /// The GPS policy, cached so a phone that starts offline keeps following the
  /// last policy it saw instead of falling back to defaults.
  Future<SyncResult<GpsPolicyDto>> gpsPolicy() => _cached(
    'gpsPolicy',
    () => api.gpsPolicy(),
    (v) => v.toJson(),
    GpsPolicyDto.fromJson,
  );

  Future<SyncResult<List<GeoPointDto>>> locations() => _cached(
    'locations',
    () => api.locations(),
    (v) => {
      'items': [for (final g in v) g.toJson()],
    },
    (json) => [
      for (final item in (json['items'] as List? ?? const []))
        GeoPointDto.fromJson(item as Map<String, dynamic>),
    ],
  );

  /// Upload of one GPS fix. [clientId] is the phone's own id for the fix: if
  /// the office has already stored that id it returns the stored fix instead of
  /// creating a second one, so a retry is safe.
  Future<GeoPointDto> recordLocation({
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? capturedAt,
    String? barcode,
    String? clientId,
  }) => api.recordLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyM: accuracyM,
    capturedAt: capturedAt,
    barcode: barcode,
    clientId: clientId,
  );

  /// Called on sign-out so cached personal data never survives on the phone.
  Future<void> wipeCache() => cache.clear();

  Future<SyncResult<T>> _cached<T>(
    String key,
    Future<T> Function() fetch,
    Map<String, dynamic> Function(T) encode,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final value = await fetch();
      final at = DateTime.now();
      await cache.write(
        key,
        jsonEncode({'at': at.millisecondsSinceEpoch, 'data': encode(value)}),
      );
      return SyncResult(value: value, stale: false, cachedAt: at);
    } on OfflineFailure {
      final raw = await cache.read(key);
      if (raw == null) rethrow;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SyncResult(
        value: decode(decoded['data'] as Map<String, dynamic>),
        stale: true,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (decoded['at'] as num).toInt(),
        ),
      );
    }
  }
}
