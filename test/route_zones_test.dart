import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/domain/route_analysis.dart';
import 'package:latlong2/latlong.dart';

const LatLng office = LatLng(16.80, 96.20);

DeliveryTripPoint point(
  String id, {
  required double lat,
  required double lng,
  int at = 0,
  double? accuracyM,
  String commissionId = 'c',
}) => DeliveryTripPoint(
  id: id,
  barcode: 'B',
  commissionId: commissionId,
  deliveryManId: 'm',
  latitude: lat,
  longitude: lng,
  accuracyM: accuracyM,
  capturedAt: at,
  createdAt: at,
);

CommissionRecord record(
  String id, {
  int at = 0,
  String manId = 'm',
  String? barcode,
}) => CommissionRecord(
  id: id,
  barcode: barcode ?? 'RCPT-${id.toUpperCase()}',
  deliveryManId: manId,
  commission: 1000,
  dateTime: at,
  staffUserId: 'staff',
  createdAt: at,
);

/// A measured row whose farthest point sits about [km] north of the office.
DeliveryRouteRow measured(
  String id,
  double km, {
  String manId = 'm',
  int at = 0,
}) {
  final near = point(
    '$id-near',
    lat: office.latitude + 0.0001,
    lng: office.longitude,
    at: at,
    accuracyM: 8,
    commissionId: id,
  );
  final far = point(
    '$id-far',
    lat: office.latitude + km / 111.19,
    lng: office.longitude,
    at: at + 60000,
    accuracyM: 8,
    commissionId: id,
  );
  return DeliveryRouteRow(
    commission: record(id, at: at, manId: manId),
    points: [near, far],
    analysis: analyzeRoute([near, far], office),
  );
}

/// A delivery for which the office kept no GPS at all.
DeliveryRouteRow unmeasured(String id, {String manId = 'm', int at = 0}) =>
    DeliveryRouteRow(
      commission: record(id, at: at, manId: manId),
      points: const [],
    );

int day(int month, int date) =>
    DateTime(2026, month, date).millisecondsSinceEpoch;

/// An explicit copy of the shop's starting configuration, so a test can never
/// disturb the shared const list.
final List<DistanceZone> _fourZones = [...defaultZones];

void main() {
  group('distance measurement', () {
    test(
      'Haversine and the production geodesic agree on a due-north point',
      () {
        // Production uses latlong2's default (Vincenty on WGS84); the spec's
        // Haversine check is the spherical reference. They must agree closely.
        const haversine = Distance(calculator: Haversine());
        const geodesic = Distance();
        // 5 km in degrees at the equator (latlong2's spherical radius).
        final far = LatLng(office.latitude + 5 / 111.32, office.longitude);
        expect(haversine(office, far), closeTo(5000, 2));
        expect(geodesic(office, far), closeTo(5000, 40));
      },
    );

    test('a point due north of the office measures its true distance', () {
      expect(measured('r1', 5).farthestKm, closeTo(5.0, 0.05));
      expect(measured('r2', 0.05).farthestKm, closeTo(0.05, 0.01));
      expect(measured('r3', 12.5).farthestKm, closeTo(12.5, 0.1));
    });

    test('the farthest point wins, once per delivery', () {
      final row = measured('r1', 3);
      expect(row.points, hasLength(2));
      expect(row.analysis!.farthest.id, 'r1-far');
      // Two fixes, but still one route for the percentages.
      final report = computeZoneReport([row], defaultZones);
      expect(report.validRoutes, 1);
      expect(report.shares.firstWhere((s) => s.zone.id == 'zone-b').count, 1);
    });
  });

  group('zone assignment', () {
    test('lower edge included, upper edge excluded', () {
      expect(zoneForKm(defaultZones, 0)!.id, 'zone-a');
      expect(zoneForKm(defaultZones, 1.999)!.id, 'zone-a');
      expect(zoneForKm(defaultZones, 2)!.id, 'zone-b'); // exact boundary
      expect(zoneForKm(defaultZones, 5)!.id, 'zone-c');
      expect(zoneForKm(defaultZones, 9.999)!.id, 'zone-c');
      expect(zoneForKm(defaultZones, 10)!.id, 'zone-d');
      expect(zoneForKm(defaultZones, 900)!.id, 'zone-d'); // open-ended
    });

    test('a disabled zone takes no part until enabled again', () {
      final zones = [
        defaultZones[0],
        defaultZones[1].copyWith(enabled: false),
        defaultZones[2],
        defaultZones[3],
      ];
      expect(zoneForKm(zones, 3), isNull); // 2–5 km is uncovered now
      expect(zoneForKm(zones, 6)!.id, 'zone-c');
    });
  });

  group('zone configuration validation', () {
    test('the default 0–2 / 2–5 / 5–10 / 10+ configuration is valid', () {
      expect(validateZones(defaultZones), isEmpty);
    });

    test('a gap between zones is rejected', () {
      final errors = validateZones(const [
        DistanceZone(id: 'a', name: 'A', minKm: 0, maxKm: 2, argb: 0xFF2E7D32),
        DistanceZone(
          id: 'c',
          name: 'C',
          minKm: 5,
          maxKm: null,
          argb: 0xFFEF6C00,
        ),
      ]);
      expect(errors, hasLength(1));
      expect(errors.single, contains('Gap'));
    });

    test('an overlap is rejected', () {
      final errors = validateZones(const [
        DistanceZone(id: 'a', name: 'A', minKm: 0, maxKm: 2, argb: 0xFF2E7D32),
        DistanceZone(
          id: 'b',
          name: 'B',
          minKm: 1.5,
          maxKm: null,
          argb: 0xFFF9A825,
        ),
      ]);
      expect(errors.single, contains('overlaps'));
    });

    test('the first zone must start at zero', () {
      final errors = validateZones(const [
        DistanceZone(id: 'a', name: 'A', minKm: 1, maxKm: 2, argb: 0xFF2E7D32),
        DistanceZone(
          id: 'b',
          name: 'B',
          minKm: 2,
          maxKm: null,
          argb: 0xFFF9A825,
        ),
      ]);
      expect(errors.single, contains('start at 0'));
    });

    test('the last zone must be open-ended', () {
      final errors = validateZones(const [
        DistanceZone(id: 'a', name: 'A', minKm: 0, maxKm: 2, argb: 0xFF2E7D32),
        DistanceZone(id: 'b', name: 'B', minKm: 2, maxKm: 5, argb: 0xFFF9A825),
      ]);
      expect(errors.single, contains('open-ended'));
    });

    test('duplicate ids are rejected', () {
      final errors = validateZones(const [
        DistanceZone(id: 'z', name: 'A', minKm: 0, maxKm: 2, argb: 0xFF2E7D32),
        DistanceZone(
          id: 'z',
          name: 'B',
          minKm: 2,
          maxKm: null,
          argb: 0xFFF9A825,
        ),
      ]);
      expect(errors.join('\n'), contains('Duplicate zone id'));
    });

    test('an inverted range is rejected', () {
      final errors = validateZones(const [
        DistanceZone(
          id: 'z',
          name: 'Broken',
          minKm: 5,
          maxKm: 2,
          argb: 0xFF2E7D32,
        ),
      ]);
      expect(errors.join('\n'), contains('ends at or before'));
    });

    test('disabling a zone in the middle leaves a gap and is rejected', () {
      final zones = [
        defaultZones[0],
        defaultZones[1].copyWith(enabled: false),
        defaultZones[2],
        defaultZones[3],
      ];
      expect(validateZones(zones).join('\n'), contains('Gap'));
    });

    test('at least one zone must be enabled', () {
      final zones = [for (final z in defaultZones) z.copyWith(enabled: false)];
      expect(validateZones(zones).single, contains('enabled'));
    });
  });

  group('zone percentages', () {
    test('counts each delivery once over the valid routes', () {
      final rows = [
        measured('r1', 1), // A
        measured('r2', 3), // B
        measured('r3', 3), // B
        measured('r4', 7), // C
        unmeasured('r5'), // excluded
      ];
      final report = computeZoneReport(rows, defaultZones);

      expect(report.validRoutes, 4);
      expect(report.excludedRoutes, 1);
      final byId = {for (final share in report.shares) share.zone.id: share};
      expect(byId['zone-a']!.count, 1);
      expect(byId['zone-b']!.count, 2);
      expect(byId['zone-c']!.count, 1);
      expect(byId['zone-d']!.count, 0);
      expect(byId['zone-a']!.percentage, 25);
      expect(byId['zone-b']!.percentage, 50);
      expect(byId['zone-c']!.percentage, 25);
      expect(
        report.shares.fold<double>(0, (sum, share) => sum + share.percentage),
        closeTo(100, 1e-9),
      );
    });

    test('display rounding never changes the real split', () {
      final report = computeZoneReport([
        measured('r1', 1),
        measured('r2', 1.5),
        measured('r3', 6),
      ], defaultZones);
      final a = report.shares.firstWhere((s) => s.zone.id == 'zone-a');
      final c = report.shares.firstWhere((s) => s.zone.id == 'zone-c');
      expect(a.percentage.toStringAsFixed(1), '66.7');
      expect(c.percentage.toStringAsFixed(1), '33.3');
      expect(a.percentage + c.percentage, closeTo(100, 1e-9));
      expect(a.count + c.count, report.validRoutes);
    });

    test('average and median of the farthest distances per zone', () {
      final report = computeZoneReport([
        measured('r1', 1),
        measured('r2', 1.5),
        measured('r3', 1.8),
      ], defaultZones);
      final a = report.shares.firstWhere((s) => s.zone.id == 'zone-a');
      expect(a.averageKm, closeTo((1 + 1.5 + 1.8) / 3, 0.01));
      expect(a.medianKm, closeTo(1.5, 0.01));
      final d = report.shares.firstWhere((s) => s.zone.id == 'zone-d');
      expect(d.averageKm, isNull);
      expect(d.medianKm, isNull);
    });

    test('zero valid routes is stated as unavailable, not 100%', () {
      final report = computeZoneReport([unmeasured('r1')], defaultZones);
      expect(report.validRoutes, 0);
      expect(report.excludedRoutes, 1);
      expect(report.shares.every((s) => s.percentage == 0), isTrue);
      expect(report.shares.every((s) => s.averageKm == null), isTrue);
      expect(
        report.shares.fold<double>(0, (sum, share) => sum + share.percentage),
        0,
      );
    });
  });

  group('GPS quality status', () {
    test('no fixes, or a single fix, is insufficient GPS data', () {
      expect(routeGpsStatus(const []), RouteGpsStatus.insufficient);
      expect(
        routeGpsStatus([point('p', lat: 16.8, lng: 96.2)]),
        RouteGpsStatus.insufficient,
      );
    });

    test('regular fixes with good accuracy are complete', () {
      expect(
        routeGpsStatus([
          point('p1', lat: 16.8, lng: 96.2, at: 0, accuracyM: 8),
          point('p2', lat: 16.801, lng: 96.201, at: 120000, accuracyM: 8),
        ]),
        RouteGpsStatus.complete,
      );
    });

    test('a reporting gap marks the route incomplete', () {
      expect(
        routeGpsStatus([
          point('p1', lat: 16.8, lng: 96.2, at: 0),
          point('p2', lat: 16.801, lng: 96.2, at: 120000),
          point('p3', lat: 16.802, lng: 96.2, at: 720000), // 10-minute gap
        ]),
        RouteGpsStatus.incomplete,
      );
    });

    test('poor accuracy marks the route incomplete', () {
      expect(
        routeGpsStatus([
          point('p1', lat: 16.8, lng: 96.2, at: 0, accuracyM: 8),
          point('p2', lat: 16.801, lng: 96.2, at: 120000, accuracyM: 300),
        ]),
        RouteGpsStatus.incomplete,
      );
    });
  });

  group('filters', () {
    final rows = [
      measured('r1', 1, at: day(10, 1)),
      measured('r2', 7, at: day(10, 3), manId: 'm2'),
      unmeasured('r3', at: day(10, 5)),
    ];

    test('date range keeps deliveries verified inside it', () {
      final kept = filterRouteRows(
        rows,
        RouteAnalysisFilter(fromMs: day(10, 2), toMs: day(10, 4)),
        defaultZones,
      );
      expect(kept.map((r) => r.commission.id), ['r2']);
    });

    test('delivery man filter', () {
      final kept = filterRouteRows(
        rows,
        const RouteAnalysisFilter(manId: 'm'),
        defaultZones,
      );
      expect(kept.map((r) => r.commission.id), ['r1', 'r3']);
    });

    test('barcode is a case-insensitive substring', () {
      final kept = filterRouteRows(
        rows,
        const RouteAnalysisFilter(barcode: 'rcpt-r2'),
        defaultZones,
      );
      expect(kept.single.commission.id, 'r2');
    });

    test('status filter separates measured from insufficient routes', () {
      final kept = filterRouteRows(
        rows,
        const RouteAnalysisFilter(status: RouteGpsStatus.insufficient),
        defaultZones,
      );
      expect(kept.single.commission.id, 'r3');
    });

    test('zone filter keeps only measured routes in that zone', () {
      final kept = filterRouteRows(
        rows,
        const RouteAnalysisFilter(zoneId: 'zone-c'),
        defaultZones,
      );
      expect(kept.single.commission.id, 'r2');
    });
  });

  test('changing zone boundaries re-analyses routes, not GPS records', () {
    final row = measured('r1', 3);
    final before = computeZoneReport([row], defaultZones);
    expect(before.shares.firstWhere((s) => s.zone.id == 'zone-b').count, 1);
    final distanceBefore = row.farthestKm;

    const widened = [
      DistanceZone(
        id: 'zone-a',
        name: 'Zone A',
        minKm: 0,
        maxKm: 5,
        argb: 0xFF2E7D32,
      ),
      DistanceZone(
        id: 'zone-b',
        name: 'Zone B',
        minKm: 5,
        maxKm: null,
        argb: 0xFFF9A825,
      ),
    ];
    expect(validateZones(widened), isEmpty);

    final after = computeZoneReport([row], widened);
    expect(after.shares.firstWhere((s) => s.zone.id == 'zone-a').count, 1);
    expect(after.shares.firstWhere((s) => s.zone.id == 'zone-b').count, 0);
    // The folders and fixes are untouched: exactly the same distance.
    expect(row.farthestKm, distanceBefore);
    expect(row.points, hasLength(2));
  });

  group('zone changes keep the bands joined', () {
    test('moving a zone\'s maximum brings the next zone with it', () {
      final moved = movedZoneBoundary(
        _fourZones,
        before: _fourZones[0], // Zone A 0–2 …
        after: _fourZones[0].copyWith(maxKm: 3), // … now 0–3
      );
      expect(moved[0].maxKm, 3);
      expect(moved[1].minKm, 3); // Zone B follows
      expect(moved[1].maxKm, 5); // its own maximum is untouched
      expect(moved[2].minKm, 5);
      expect(validateZones(moved), isEmpty);
    });

    test('moving a zone\'s minimum brings the previous zone with it', () {
      final moved = movedZoneBoundary(
        _fourZones,
        before: _fourZones[1], // Zone B 2–5 …
        after: _fourZones[1].copyWith(minKm: 1.5), // … now starts at 1.5
      );
      expect(moved[0].maxKm, 1.5);
      expect(moved[1].minKm, 1.5);
      expect(moved[2].maxKm, 10);
      expect(validateZones(moved), isEmpty);
    });

    test('closing the open-ended zone closes with it', () {
      final moved = movedZoneBoundary(
        _fourZones,
        before: _fourZones[3], // Zone D 10+
        after: _fourZones[3].copyWith(maxKm: 25), // now 10–25
      );
      expect(moved[3].maxKm, 25);
      expect(validateZones(moved).single, contains('open-ended'));
    });

    test('changing only the name or colour moves no boundary', () {
      final moved = movedZoneBoundary(
        _fourZones,
        before: _fourZones[1],
        after: _fourZones[1].copyWith(name: 'Nearby', argb: 0xFF112233),
      );
      expect(moved[1].name, 'Nearby');
      expect(moved[1].argb, 0xFF112233);
      // A pencil edit is not a reorder, so every band is exactly as it was.
      for (var i = 0; i < _fourZones.length; i++) {
        expect(moved[i].minKm, _fourZones[i].minKm);
        expect(moved[i].maxKm, _fourZones[i].maxKm);
      }
      expect(validateZones(moved), isEmpty);
    });

    test('deleting a zone gives its band to the neighbour, leaving no gap', () {
      final after = withoutZone(_fourZones, _fourZones[1]); // drop Zone B 2–5
      expect(after, hasLength(3));
      expect(after[0].maxKm, 5); // Zone A now covers 0–5
      expect(after[1].minKm, 5);
      expect(after[1].maxKm, 10);
      expect(validateZones(after), isEmpty);
      expect(zoneForKm(after, 3)!.id, 'zone-a');
    });

    test('deleting the first zone makes the next one start at zero', () {
      final after = withoutZone(_fourZones, _fourZones[0]);
      expect(after.first.minKm, 0);
      expect(validateZones(after), isEmpty);
    });

    test('deleting the open-ended zone leaves the previous zone open', () {
      final after = withoutZone(_fourZones, _fourZones[3]);
      expect(after.last.maxKm, isNull);
      expect(after.last.minKm, 5);
      expect(validateZones(after), isEmpty);
    });
  });

  group('zone settings JSON', () {
    test('nothing saved yet falls back to the defaults', () {
      expect(zonesFromJson(null), defaultZones);
      expect(zonesFromJson(''), defaultZones);
    });

    test('saved zones round-trip, including the open-ended one', () {
      const zones = [
        DistanceZone(
          id: 'z1',
          name: 'Near',
          minKm: 0,
          maxKm: 1.5,
          argb: 0xFF112233,
          sortOrder: 2,
          enabled: false,
        ),
        DistanceZone(
          id: 'z2',
          name: 'Far',
          minKm: 1.5,
          maxKm: null,
          argb: 0xFF445566,
          sortOrder: 3,
        ),
      ];
      final restored = zonesFromJson(zonesToJson(zones));
      expect(restored, hasLength(2));
      expect(restored.first.id, 'z1');
      expect(restored.first.name, 'Near');
      expect(restored.first.minKm, 0);
      expect(restored.first.maxKm, 1.5);
      expect(restored.first.argb, 0xFF112233);
      expect(restored.first.sortOrder, 2);
      expect(restored.first.enabled, isFalse);
      expect(restored.last.maxKm, isNull);
      expect(restored.last.enabled, isTrue);
    });

    test('an unreadable value falls back to the defaults', () {
      expect(zonesFromJson('not json at all'), defaultZones);
      expect(zonesFromJson('[1, 2, 3]'), defaultZones);
    });
  });
}
