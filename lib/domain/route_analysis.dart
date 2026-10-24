import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../data/models/models.dart';

/// How one kept route measures against the office centre point.
///
/// The number staff ask for is [maxDistanceM]: how far the *farthest single GPS
/// point* of the route got from the centre. [meanDistanceM] is there to tell a
/// route that stayed far all the way from one that merely spiked once, and
/// [farthest] says which point produced the maximum so it can be shown on the
/// map instead of quoted as a bare number.
class RouteAnalysis {
  const RouteAnalysis({
    required this.maxDistanceM,
    required this.meanDistanceM,
    required this.farthest,
  });

  final double maxDistanceM;
  final double meanDistanceM;
  final DeliveryTripPoint farthest;
}

/// Measures [points] from [centre]. An empty route has nothing to measure, so
/// it returns null rather than a meaningless zero.
RouteAnalysis? analyzeRoute(List<DeliveryTripPoint> points, LatLng centre) {
  if (points.isEmpty) return null;
  const distance = Distance();
  var total = 0.0;
  var max = -1.0;
  var farthest = points.first;
  for (final point in points) {
    final metres = distance(centre, LatLng(point.latitude, point.longitude));
    total += metres;
    if (metres > max) {
      max = metres;
      farthest = point;
    }
  }
  return RouteAnalysis(
    maxDistanceM: max,
    meanDistanceM: total / points.length,
    farthest: farthest,
  );
}

/// Points split into continuous stretches. A new stretch starts when the phone
/// stopped reporting ([maxGap]) or the jump is too far to be a road leg
/// ([maxJumpM]). Nothing is drawn across a break, so a missing stretch is never
/// shown as a route the man travelled.
List<List<DeliveryTripPoint>> routeSegments(
  List<DeliveryTripPoint> points, {
  Duration maxGap = const Duration(minutes: 5),
  double maxJumpM = 1000,
}) {
  const distance = Distance();
  final segments = <List<DeliveryTripPoint>>[];
  var current = <DeliveryTripPoint>[];
  for (final point in points) {
    if (current.isNotEmpty) {
      final previous = current.last;
      final gapMs = point.capturedAt - previous.capturedAt;
      final jumpM = distance(
        LatLng(previous.latitude, previous.longitude),
        LatLng(point.latitude, point.longitude),
      );
      if (gapMs > maxGap.inMilliseconds || jumpM > maxJumpM) {
        segments.add(current);
        current = <DeliveryTripPoint>[];
      }
    }
    current.add(point);
  }
  if (current.isNotEmpty) segments.add(current);
  return segments;
}

/// Whether [lat]/[lng] can be a real coordinate on the globe.
bool validCoordinates(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;

// ---- Distance zones ----

/// A circular distance zone around the office centre. A delivery's zone is the
/// one holding its *farthest* GPS point. Each zone includes its lower boundary
/// and excludes its upper one ([maxKm]); the final zone is open-ended
/// ([maxKm] null), so every nonnegative distance lands in exactly one zone.
class DistanceZone {
  const DistanceZone({
    required this.id,
    required this.name,
    required this.minKm,
    required this.maxKm,
    required this.argb,
    this.sortOrder = 0,
    this.enabled = true,
  });

  final String id;
  final String name;
  final double minKm;

  /// Exclusive upper boundary in kilometres; null = the final open-ended zone.
  final double? maxKm;

  /// Display colour as a 32-bit ARGB int (the UI turns it into a Color), so
  /// the zone can live in settings JSON without a Flutter dependency.
  final int argb;

  final int sortOrder;
  final bool enabled;

  String get rangeLabel => maxKm == null
      ? '${trimKm(minKm)}+ km'
      : '${trimKm(minKm)}–${trimKm(maxKm!)} km';

  DistanceZone copyWith({
    String? name,
    double? minKm,
    double? maxKm,
    int? argb,
    int? sortOrder,
    bool? enabled,
    bool clearMax = false,
  }) => DistanceZone(
    id: id,
    name: name ?? this.name,
    minKm: minKm ?? this.minKm,
    maxKm: clearMax ? null : (maxKm ?? this.maxKm),
    argb: argb ?? this.argb,
    sortOrder: sortOrder ?? this.sortOrder,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'min_km': minKm,
    'max_km': maxKm,
    'argb': argb,
    'sort_order': sortOrder,
    'enabled': enabled,
  };

  factory DistanceZone.fromMap(Map<String, dynamic> m) => DistanceZone(
    id: m['id'] as String,
    name: m['name'] as String,
    minKm: (m['min_km'] as num).toDouble(),
    maxKm: (m['max_km'] as num?)?.toDouble(),
    argb: (m['argb'] as num).toInt(),
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    enabled: (m['enabled'] as bool?) ?? true,
  );
}

/// A distance without trailing zeroes: `2`, `2.5`.
String trimKm(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// The shop's starting configuration — Zone A 0–2, B over 2–5, C over 5–10,
/// D over 10 km. Defaults only; every boundary is editable later.
const List<DistanceZone> defaultZones = [
  DistanceZone(
    id: 'zone-a',
    name: 'Zone A',
    minKm: 0,
    maxKm: 2,
    argb: 0xFF2E7D32,
  ),
  DistanceZone(
    id: 'zone-b',
    name: 'Zone B',
    minKm: 2,
    maxKm: 5,
    argb: 0xFFF9A825,
  ),
  DistanceZone(
    id: 'zone-c',
    name: 'Zone C',
    minKm: 5,
    maxKm: 10,
    argb: 0xFFEF6C00,
  ),
  DistanceZone(
    id: 'zone-d',
    name: 'Zone D',
    minKm: 10,
    maxKm: null,
    argb: 0xFFC62828,
  ),
];

/// Settings keys shared by the Route Analysis screens and the delivery-routes
/// centre point (the same office coordinate is used everywhere).
const String officeNameSettingKey = 'routeMap.officeName';
const String centreLatSettingKey = 'routeMap.centerLat';
const String centreLngSettingKey = 'routeMap.centerLng';
const String zonesSettingKey = 'routeMap.zones';

/// Zones from settings, or the defaults when nothing is saved yet or the
/// stored value cannot be read — a bad value must never blank the screen.
List<DistanceZone> zonesFromJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return defaultZones;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return defaultZones;
    final zones = [
      for (final entry in decoded)
        if (entry is Map<String, dynamic>) DistanceZone.fromMap(entry),
    ];
    return zones.isEmpty ? defaultZones : zones;
  } on Exception {
    return defaultZones;
  }
}

String zonesToJson(List<DistanceZone> zones) =>
    jsonEncode([for (final zone in zones) zone.toMap()]);

/// The zones that take part in analysis, display order.
List<DistanceZone> enabledZones(List<DistanceZone> zones) => [
  for (final zone in zones)
    if (zone.enabled) zone,
]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// The zone containing [km], or null when the enabled zones leave that
/// distance uncovered. Lower boundary included, upper excluded; if an old
/// configuration ever overlaps, the tightest band wins.
DistanceZone? zoneForKm(List<DistanceZone> zones, double km) {
  DistanceZone? found;
  for (final zone in zones) {
    if (!zone.enabled) continue;
    if (km >= zone.minKm && (zone.maxKm == null || km < zone.maxKm!)) {
      if (found == null || zone.minKm > found.minKm) found = zone;
    }
  }
  return found;
}

/// Problems with a zone configuration. Empty means it can be saved: the
/// enabled zones start at 0, touch without gaps or overlaps, and the last one
/// is open-ended, so every nonnegative distance falls in exactly one zone.
/// A disabled zone takes no part until it is enabled again.
List<String> validateZones(List<DistanceZone> zones) {
  final errors = <String>[];
  final ids = <String>{};
  for (final zone in zones) {
    if (!ids.add(zone.id)) errors.add('Duplicate zone id "${zone.id}".');
    if (zone.minKm < 0) errors.add('"${zone.name}" starts below 0 km.');
    if (zone.maxKm != null && zone.maxKm! <= zone.minKm) {
      errors.add('"${zone.name}" ends at or before it starts.');
    }
  }
  final enabled = [...enabledZones(zones)]
    ..sort((a, b) => a.minKm.compareTo(b.minKm));
  if (enabled.isEmpty) {
    errors.add('At least one zone must be enabled.');
    return errors;
  }
  if (enabled.first.minKm != 0) {
    errors.add('The first enabled zone must start at 0 km.');
  }
  if (enabled.last.maxKm != null) {
    errors.add('The last enabled zone must be open-ended (no maximum).');
  }
  if (enabled.where((z) => z.maxKm == null).length > 1) {
    errors.add('Only the last zone can be open-ended.');
  }
  for (var i = 0; i + 1 < enabled.length; i++) {
    final upper = enabled[i].maxKm;
    if (upper == null) continue;
    final next = enabled[i + 1];
    if (next.minKm < upper) {
      errors.add('"${next.name}" overlaps "${enabled[i].name}".');
    } else if (next.minKm > upper) {
      errors.add('Gap between "${enabled[i].name}" and "${next.name}".');
    }
  }
  return errors;
}

/// The zones after [after] replaces the zone that looked like [before],
/// keeping the bands touching: a boundary that moved takes the zone on the
/// other side with it, so changing one diameter never leaves a gap or an
/// overlap behind. Name/colour-only edits change no boundary.
List<DistanceZone> movedZoneBoundary(
  List<DistanceZone> zones, {
  required DistanceZone before,
  required DistanceZone after,
}) => [
  for (final zone in zones)
    if (zone.id == after.id)
      after
    else if (before.maxKm != null &&
        after.maxKm != null &&
        zone.minKm == before.maxKm)
      zone.copyWith(minKm: after.maxKm)
    else if (before.minKm > 0 && zone.maxKm == before.minKm)
      zone.copyWith(maxKm: after.minKm)
    else
      zone,
];

/// The zones after [removed] is deleted: its band joins the neighbouring
/// zone, so the remaining zones still cover every distance instead of
/// leaving a gap that blocks saving.
List<DistanceZone> withoutZone(List<DistanceZone> zones, DistanceZone removed) {
  final remaining = [
    for (final zone in zones)
      if (zone.id != removed.id) zone,
  ];
  return [
    for (final zone in remaining)
      if (zone.maxKm == removed.minKm)
        removed.maxKm == null
            ? zone.copyWith(clearMax: true)
            : zone.copyWith(maxKm: removed.maxKm)
      else if (removed.minKm == 0 && zone.minKm == removed.maxKm)
        zone.copyWith(minKm: 0)
      else
        zone,
  ];
}

// ---- GPS quality ----

/// What the kept GPS history can honestly support for one delivery. Stated
/// per route, never guessed around: fewer than two fixes is not a route, and
/// a route with reporting gaps or poor accuracy is marked incomplete rather
/// than smoothed over.
enum RouteGpsStatus {
  complete('COMPLETE'),
  incomplete('INCOMPLETE'),
  insufficient('INSUFFICIENT GPS');

  const RouteGpsStatus(this.label);
  final String label;
}

/// Fixes claiming worse than this accuracy hold a route back from COMPLETE —
/// a 300 m "accuracy" can put the phone in the next block.
const double poorAccuracyM = 150;

RouteGpsStatus routeGpsStatus(List<DeliveryTripPoint> points) {
  if (points.length < 2) return RouteGpsStatus.insufficient;
  if (routeSegments(points).length > 1) return RouteGpsStatus.incomplete;
  if (points.any((p) => (p.accuracyM ?? 0) > poorAccuracyM)) {
    return RouteGpsStatus.incomplete;
  }
  return RouteGpsStatus.complete;
}

// ---- Analysis rows ----

/// One successful delivery with its kept route, already measured from the
/// office centre.
class DeliveryRouteRow {
  const DeliveryRouteRow({
    required this.commission,
    required this.points,
    this.analysis,
  });

  final CommissionRecord commission;

  /// The route's kept fixes, oldest first; empty when the office kept none.
  final List<DeliveryTripPoint> points;

  /// Null when no centre point is set or the route holds no fixes.
  final RouteAnalysis? analysis;

  RouteGpsStatus get status => routeGpsStatus(points);

  /// Farthest point from the centre in kilometres; null when unmeasured.
  double? get farthestKm =>
      analysis == null ? null : analysis!.maxDistanceM / 1000;
}

/// Builds one row per successful delivery from [pointsByCommission]
/// (commission id → its kept fixes, oldest first). The centre is read from
/// settings by the caller: without one nothing is measured.
List<DeliveryRouteRow> buildRouteRows({
  required List<CommissionRecord> records,
  required Map<String, List<DeliveryTripPoint>> pointsByCommission,
  required LatLng? centre,
}) => [
  for (final record in records)
    DeliveryRouteRow(
      commission: record,
      points: pointsByCommission[record.id] ?? const [],
      analysis: centre == null
          ? null
          : analyzeRoute(pointsByCommission[record.id] ?? const [], centre),
    ),
];

/// Which analysed rows the Route Analysis filters keep. The barcode is a
/// case-insensitive substring match; a zone filter only keeps routes that
/// were measured *and* fall in that zone.
class RouteAnalysisFilter {
  const RouteAnalysisFilter({
    this.fromMs,
    this.toMs,
    this.manId,
    this.barcode = '',
    this.zoneId,
    this.status,
  });

  final int? fromMs;
  final int? toMs;
  final String? manId;
  final String barcode;
  final String? zoneId;
  final RouteGpsStatus? status;

  RouteAnalysisFilter copyWith({
    int? fromMs,
    int? toMs,
    String? manId,
    String? barcode,
    String? zoneId,
    RouteGpsStatus? status,
  }) => RouteAnalysisFilter(
    fromMs: fromMs ?? this.fromMs,
    toMs: toMs ?? this.toMs,
    manId: manId ?? this.manId,
    barcode: barcode ?? this.barcode,
    zoneId: zoneId ?? this.zoneId,
    status: status ?? this.status,
  );
}

List<DeliveryRouteRow> filterRouteRows(
  List<DeliveryRouteRow> rows,
  RouteAnalysisFilter filter,
  List<DistanceZone> zones,
) => [
  for (final row in rows)
    if (_keeps(row, filter, zones)) row,
];

bool _keeps(
  DeliveryRouteRow row,
  RouteAnalysisFilter f,
  List<DistanceZone> zones,
) {
  if (f.manId != null && row.commission.deliveryManId != f.manId) {
    return false;
  }
  if (f.fromMs != null && row.commission.dateTime < f.fromMs!) return false;
  if (f.toMs != null && row.commission.dateTime > f.toMs!) return false;
  final query = f.barcode.trim().toLowerCase();
  if (query.isNotEmpty &&
      !row.commission.barcode.toLowerCase().contains(query)) {
    return false;
  }
  if (f.status != null && row.status != f.status) return false;
  if (f.zoneId != null) {
    final km = row.farthestKm;
    if (km == null || zoneForKm(zones, km)?.id != f.zoneId) return false;
  }
  return true;
}

// ---- Zone percentages ----

/// One enabled zone's slice of the analysed routes.
class ZoneShare {
  const ZoneShare({
    required this.zone,
    required this.count,
    required this.percentage,
    this.averageKm,
    this.medianKm,
  });

  final DistanceZone zone;
  final int count;

  /// Share of the valid routes, 0–100 (raw; round only for display).
  final double percentage;
  final double? averageKm;
  final double? medianKm;
}

/// Zone shares over a filtered set of rows. Each delivery counts once;
/// routes without usable GPS are held out of the denominator and counted in
/// [excludedRoutes] separately, so the shares add to 100 whenever at least
/// one valid route exists.
class ZoneReport {
  const ZoneReport({
    required this.shares,
    required this.validRoutes,
    required this.excludedRoutes,
  });

  final List<ZoneShare> shares;
  final int validRoutes;
  final int excludedRoutes;
}

/// The zone of each route here is derived from its distance (not stored), so
/// changing the zone boundaries re-analyses every route without touching a
/// single GPS record.
ZoneReport computeZoneReport(
  List<DeliveryRouteRow> rows,
  List<DistanceZone> zones,
) {
  final active = enabledZones(zones);
  final perZone = <String, List<double>>{
    for (final zone in active) zone.id: [],
  };
  var excluded = 0;
  for (final row in rows) {
    final km = row.farthestKm;
    final zone = km == null ? null : zoneForKm(zones, km);
    if (km == null || zone == null) {
      excluded++;
      continue;
    }
    perZone[zone.id]!.add(km);
  }
  final total = rows.length - excluded;
  return ZoneReport(
    shares: [
      for (final zone in active)
        ZoneShare(
          zone: zone,
          count: perZone[zone.id]!.length,
          percentage: total == 0 ? 0 : perZone[zone.id]!.length * 100 / total,
          averageKm: _average(perZone[zone.id]!),
          medianKm: _median(perZone[zone.id]!),
        ),
    ],
    validRoutes: total,
    excludedRoutes: excluded,
  );
}

double? _average(List<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
