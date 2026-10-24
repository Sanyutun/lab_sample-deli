import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/route_analysis.dart';
import 'common.dart';
import 'route_analysis_settings_screen.dart';
import 'zone_map.dart';

/// Admin: every successful delivery measured against the office centre — how
/// far its kept GPS route got at the farthest point, which distance zone that
/// falls in, and each zone's share of the analysed routes.
///
/// Filters (date range, delivery man, barcode, zone, GPS status) drive the
/// summary, the list and the map together. As everywhere else: a route shows
/// where the phone was, never proof that a test was done, and it never
/// changes a commission.
class RouteAnalysisScreen extends StatefulWidget {
  const RouteAnalysisScreen({super.key});

  @override
  State<RouteAnalysisScreen> createState() => _RouteAnalysisScreenState();
}

class _RouteAnalysisScreenState extends State<RouteAnalysisScreen> {
  final MapController _map = MapController();
  final TextEditingController _barcode = TextEditingController();

  List<DeliveryMan> _men = [];
  Map<String, String> _manNames = {};
  List<DistanceZone> _zones = defaultZones;
  LatLng? _centre;

  /// Every active delivery with its kept route, newest first.
  List<DeliveryRouteRow> _rows = [];

  RouteAnalysisFilter _filter = const RouteAnalysisFilter();
  DeliveryRouteRow? _selected;

  bool _showZones = true;
  bool _showLine = true;
  bool _showPoints = true;

  bool _loading = true;
  bool _mapReady = false;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _barcode.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.all();
    final zones = zonesFromJson(await services.settings.get(zonesSettingKey));
    final lat = double.tryParse(
      (await services.settings.get(centreLatSettingKey)) ?? '',
    );
    final lng = double.tryParse(
      (await services.settings.get(centreLngSettingKey)) ?? '',
    );
    final records = await services.commissions.all(status: RecordStatus.active);
    // One pass over every man's kept points, so changing the man filter or
    // refreshing never refetches anything.
    final pointsByCommission = <String, List<DeliveryTripPoint>>{};
    for (final man in men) {
      for (final point in await services.trips.routePointsFor(man.id)) {
        (pointsByCommission[point.commissionId] ??= []).add(point);
      }
    }
    if (!mounted) return;
    final centre = validCoordinates(lat, lng) ? LatLng(lat!, lng!) : null;
    setState(() {
      _men = men;
      _manNames = {for (final man in men) man.id: man.name};
      _zones = zones;
      _centre = centre;
      _rows = buildRouteRows(
        records: records,
        pointsByCommission: pointsByCommission,
        centre: centre,
      );
      _loading = false;
    });
    _syncSelection();
  }

  /// A new filter set: re-pick the selected route against it and frame it.
  void _changeFilter(RouteAnalysisFilter filter) {
    setState(() {
      _filter = filter;
      _selected = null;
    });
    _syncSelection();
  }

  /// Points the selection at a row the current filters keep (the first one
  /// when the old pick fell out) and frames it on the map.
  void _syncSelection() {
    final filtered = filterRouteRows(_rows, _filter, _zones);
    DeliveryRouteRow? match;
    for (final row in filtered) {
      if (row.commission.id == _selected?.commission.id) match = row;
    }
    final next = match ?? (filtered.isEmpty ? null : filtered.first);
    final changed = next?.commission.id != _selected?.commission.id;
    _selected = next;
    if (changed) {
      _fitted = false;
      _fitOnce();
    }
  }

  /// Frames the selected route (and the centre it is measured from) the first
  /// time it is shown; panning is never fought afterwards.
  void _fitOnce() {
    if (_fitted || !_mapReady) return;
    final row = _selected;
    if (row == null) {
      final centre = _centre;
      if (centre == null) return;
      _fitted = true;
      _map.move(centre, 11);
      return;
    }
    if (row.points.isEmpty) return;
    _fitted = true;
    final coords = [
      for (final p in row.points) LatLng(p.latitude, p.longitude),
      ?_centre,
    ];
    if (coords.length == 1) {
      _map.move(coords.first, 15);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(coords),
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  void _select(DeliveryRouteRow row) => setState(() {
    _selected = row;
    _fitted = false;
    _fitOnce();
  });

  bool get _filterActive =>
      _filter.fromMs != null ||
      _filter.toMs != null ||
      _filter.manId != null ||
      _filter.barcode.isNotEmpty ||
      _filter.zoneId != null ||
      _filter.status != null;

  Future<void> _pickDate({required bool from}) async {
    final current =
        (from ? _filter.fromMs : _filter.toMs) ??
        DateTime.now().millisecondsSinceEpoch;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.fromMillisecondsSinceEpoch(current),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _filter = from
          ? _filter.copyWith(fromMs: day.millisecondsSinceEpoch)
          : _filter.copyWith(
              toMs: day
                  .add(const Duration(days: 1))
                  .subtract(const Duration(milliseconds: 1))
                  .millisecondsSinceEpoch,
            );
    });
    _syncSelection();
  }

  String _dateLabel(int? ms, String which) => ms == null
      ? '$which: any'
      : '$which: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms))}';

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RouteAnalysisSettingsScreen()),
    );
    // The centre or the zones may have changed; re-measure everything.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PageScaffold(
        title: 'Route Analysis',
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final filtered = filterRouteRows(_rows, _filter, _zones);
    final report = computeZoneReport(filtered, _zones);
    final selected = _selected;
    return PageScaffold(
      title: 'Route Analysis',
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Route analysis settings',
          onPressed: _openSettings,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _load,
        ),
      ],
      body: Column(
        children: [
          _filters(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _statsCard(report),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 4, child: _routesList(filtered)),
                Expanded(flex: 6, child: _mapArea(selected)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- filters ----

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(from: true),
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(_dateLabel(_filter.fromMs, 'From')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickDate(from: false),
                icon: const Icon(Icons.event, size: 16),
                label: Text(_dateLabel(_filter.toMs, 'To')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _barcode,
                  onChanged: (v) {
                    setState(() => _filter = _filter.copyWith(barcode: v));
                    _syncSelection();
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Receipt barcode',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter.manId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Delivery man',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final man in _men)
                      DropdownMenuItem(value: man.id, child: Text(man.name)),
                  ],
                  onChanged: (v) => _changeFilter(_filter.copyWith(manId: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter.zoneId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Distance zone',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final zone in enabledZones(_zones))
                      DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                  ],
                  onChanged: (v) => _changeFilter(_filter.copyWith(zoneId: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<RouteGpsStatus>(
                  initialValue: _filter.status,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Route status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<RouteGpsStatus>(
                      value: null,
                      child: Text('All'),
                    ),
                    for (final status in RouteGpsStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(status.label, style: fontSize12),
                      ),
                  ],
                  onChanged: (v) => _changeFilter(_filter.copyWith(status: v)),
                ),
              ),
              if (_filterActive) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    _barcode.clear();
                    _changeFilter(const RouteAnalysisFilter());
                  },
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static const TextStyle fontSize12 = TextStyle(fontSize: 12);

  // ---- zone summary ----

  Widget _statsCard(ZoneReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Zone summary',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${report.validRoutes} valid route(s) · '
                  '${report.excludedRoutes} excluded (insufficient GPS)',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            if (report.validRoutes == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No valid routes in this range — percentages need at '
                  'least one route with usable GPS.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: [
                    for (final share in report.shares) _shareRow(share),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One zone's line: swatch, name, range, count, percentage and a
  /// horizontal bar of that percentage.
  Widget _shareRow(ZoneShare share) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: zoneColor(share.zone),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: Text(
              share.zone.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              share.zone.rangeLabel,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          SizedBox(
            width: 66,
            child: Text(
              '${share.count} route(s)',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${share.percentage.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share.percentage / 100,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: zoneColor(share.zone),
              ),
            ),
          ),
          SizedBox(
            width: 132,
            child: share.averageKm == null
                ? const Text(
                    ' no routes',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  )
                : Text(
                    ' avg ${share.averageKm!.toStringAsFixed(2)} · '
                    'med ${share.medianKm!.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
          ),
        ],
      ),
    );
  }

  // ---- routes list ----

  Widget _routesList(List<DeliveryRouteRow> filtered) {
    if (filtered.isEmpty) {
      return EmptyState(
        message: _rows.isEmpty
            ? 'No successful deliveries yet.\nRoutes appear here once a '
                  'receipt is delivered while the companion app sends GPS.'
            : 'No deliveries match these filters.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final row = filtered[index];
        final km = row.farthestKm;
        final zone = km == null ? null : zoneForKm(_zones, km);
        final parts = [
          _manNames[row.commission.deliveryManId] ?? 'Unknown',
          if (km != null) 'farthest ${km.toStringAsFixed(2)} km',
          if (zone != null) zone.name,
        ];
        return ListTile(
          dense: true,
          selected: row.commission.id == _selected?.commission.id,
          title: Text(
            '${row.commission.barcode} · ${fmtDate(row.commission.dateTime)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            parts.join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: statusChip(row.status.label),
          onTap: () => _select(row),
        );
      },
    );
  }

  // ---- map ----

  Widget _mapArea(DeliveryRouteRow? selected) {
    final centre = _centre;
    if (centre == null) {
      return const EmptyState(
        message:
            'Office centre not set.\nOpen Route Analysis settings (gear '
            'icon) and pick the office location — every distance is '
            'measured from there.',
      );
    }
    return Column(
      children: [
        _mapToggles(),
        Expanded(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: selected != null && selected.points.isNotEmpty
                  ? LatLng(
                      selected.points.first.latitude,
                      selected.points.first.longitude,
                    )
                  : centre,
              initialZoom: 14,
              onMapReady: () {
                _mapReady = true;
                _fitOnce();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'lab_commission',
              ),
              if (_showZones) ...zoneLayers(centre: centre, zones: _zones),
              PolylineLayer(
                polylines: [
                  if (_showLine && selected != null)
                    for (final segment in routeSegments(selected.points))
                      if (segment.length > 1)
                        Polyline(
                          points: [
                            for (final p in segment)
                              LatLng(p.latitude, p.longitude),
                          ],
                          strokeWidth: 4,
                          color: Colors.teal.shade600,
                        ),
                  // Centre to the farthest point: the measured distance.
                  if (_showLine && selected?.analysis != null)
                    Polyline(
                      points: [
                        centre,
                        LatLng(
                          selected!.analysis!.farthest.latitude,
                          selected.analysis!.farthest.longitude,
                        ),
                      ],
                      strokeWidth: 2,
                      color: Colors.red.shade700,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (selected != null && _showPoints)
                    for (var i = 0; i < selected.points.length; i++)
                      _pointMarker(selected, i),
                  // With the point markers hidden the farthest one still
                  // needs to be findable on the map.
                  if (selected?.analysis != null && !_showPoints)
                    _farthestMarker(selected!),
                  Marker(
                    point: centre,
                    width: 36,
                    height: 36,
                    child: const Tooltip(
                      message: 'Office centre',
                      child: Icon(Icons.place, size: 30, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapToggles() {
    Widget chip(String label, bool value, void Function(bool) set) =>
        FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: value,
          onSelected: set,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          chip('Zones', _showZones, (v) => setState(() => _showZones = v)),
          const SizedBox(width: 6),
          chip('Route line', _showLine, (v) => setState(() => _showLine = v)),
          const SizedBox(width: 6),
          chip(
            'GPS points',
            _showPoints,
            (v) => setState(() => _showPoints = v),
          ),
        ],
      ),
    );
  }

  Marker _pointMarker(DeliveryRouteRow row, int index) {
    final point = row.points[index];
    final farthest = identical(point, row.analysis?.farthest);
    final fromCentreM = const Distance()(
      _centre!,
      LatLng(point.latitude, point.longitude),
    );
    final tooltip =
        '${index + 1} · ${fmtDate(point.capturedAt)} · '
        '${_km(fromCentreM)} from centre';
    return Marker(
      point: LatLng(point.latitude, point.longitude),
      width: 32,
      height: 32,
      child: Tooltip(
        message: tooltip,
        child: CircleAvatar(
          radius: 14,
          backgroundColor: farthest ? Colors.red : Colors.teal,
          child: farthest
              ? const Icon(Icons.my_location, size: 16, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
        ),
      ),
    );
  }

  Marker _farthestMarker(DeliveryRouteRow row) {
    final farthest = row.analysis!.farthest;
    final km = row.farthestKm!.toStringAsFixed(2);
    return Marker(
      point: LatLng(farthest.latitude, farthest.longitude),
      width: 32,
      height: 32,
      child: Tooltip(
        message:
            'Farthest point · $km km from centre · '
            '${fmtDate(farthest.capturedAt)}',
        child: const CircleAvatar(
          radius: 14,
          backgroundColor: Colors.red,
          child: Icon(Icons.my_location, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  static String _km(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(2)} km'
      : '${metres.round()} m';
}
