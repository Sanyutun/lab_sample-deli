import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/route_analysis.dart';
import 'common.dart';

/// Admin: every route kept for one delivery man, drawn one at a time, measured
/// against the office centre point.
///
/// The centre is this software's own location (set from this screen, later the
/// device's own position). The headline number is how far the *farthest single
/// GPS point* of a route got from it — the list is sorted farthest-first so
/// "which deliveries went furthest from the shop" is answerable at a glance.
///
/// As everywhere else, a route shows where the phone was, never proof that a
/// test was done: gaps are stated rather than drawn across.
class DeliveryRoutesScreen extends StatefulWidget {
  const DeliveryRoutesScreen({super.key});

  @override
  State<DeliveryRoutesScreen> createState() => _DeliveryRoutesScreenState();
}

/// One delivery's route, already measured against the centre point.
class _Route {
  _Route({
    required this.commission,
    required this.points,
    required this.analysis,
  });

  final CommissionRecord commission;
  final List<DeliveryTripPoint> points;
  final RouteAnalysis? analysis;
}

class _DeliveryRoutesScreenState extends State<DeliveryRoutesScreen> {
  static const String _centreLatKey = 'routeMap.centerLat';
  static const String _centreLngKey = 'routeMap.centerLng';

  /// Metres from the centre beyond which a route is flagged OVER; null (or
  /// unset) means no limit yet.
  static const String _radiusKey = 'routeMap.radiusM';

  final MapController _map = MapController();

  List<DeliveryMan> _men = [];
  String? _manId;

  /// Null until the routes of the selected man have been read, so the screen
  /// never claims "no routes" while it is still fetching them.
  List<_Route>? _routes;
  _Route? _selected;

  LatLng? _centre;
  double? _radiusM;
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
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.all();
    final lat = double.tryParse(
      (await services.settings.get(_centreLatKey)) ?? '',
    );
    final lng = double.tryParse(
      (await services.settings.get(_centreLngKey)) ?? '',
    );
    final radius = double.tryParse(
      (await services.settings.get(_radiusKey)) ?? '',
    );
    if (!mounted) return;
    setState(() {
      _men = men;
      _centre = _isReal(lat, lng) ? LatLng(lat!, lng!) : null;
      _radiusM = radius == null || radius.isNaN || radius < 0 ? null : radius;
      if (_manId == null && men.isNotEmpty) _manId = men.first.id;
      _loading = false;
    });
    if (_manId != null) await _loadRoutes(_manId!);
  }

  static bool _isReal(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  Future<void> _loadRoutes(String manId) async {
    final services = AppScope.of(context);
    final centre = _centre;
    final commissions = await services.commissions.all(
      deliveryManId: manId,
      status: RecordStatus.active,
    );
    final points = await services.trips.routePointsFor(manId);
    final byCommission = <String, List<DeliveryTripPoint>>{};
    for (final point in points) {
      (byCommission[point.commissionId] ??= []).add(point);
    }
    final routes = <_Route>[];
    for (final commission in commissions) {
      final group = byCommission[commission.id];
      if (group == null || group.isEmpty) continue;
      routes.add(
        _Route(
          commission: commission,
          points: group,
          analysis: centre == null ? null : analyzeRoute(group, centre),
        ),
      );
    }
    // With a centre the question is "how far did each route get", so order by
    // that; without one the only useful order is newest delivery first.
    routes.sort((a, b) {
      final da = a.analysis?.maxDistanceM;
      final db = b.analysis?.maxDistanceM;
      if (da != null && db != null && da != db) return db.compareTo(da);
      return b.commission.dateTime.compareTo(a.commission.dateTime);
    });
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _selected = routes.isEmpty ? null : routes.first;
      _fitted = false;
    });
    _fitOnce();
  }

  /// Frames the route (and the centre it is measured from) the first time it is
  /// shown. Later selections re-fit too, but panning is never fought: [_fitted]
  /// is only reset when a different route is selected.
  void _fitOnce() {
    final route = _selected;
    if (_fitted || !_mapReady || route == null || route.points.isEmpty) return;
    _fitted = true;
    final coords = [
      for (final p in route.points) LatLng(p.latitude, p.longitude),
      ?_centre,
    ];
    if (coords.length == 1) {
      _map.move(coords.first, 16);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(coords),
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  /// Selects a route — from the list, the farthest-of-all headline, or the map.
  void _select(_Route route) => setState(() {
    _selected = route;
    _fitted = false;
    _fitOnce();
  });

  Future<void> _editCentre() async {
    final services = AppScope.of(context);
    final picked = await _pickCentre();
    if (picked == null || !mounted) return;
    await services.settings.set(_centreLatKey, picked.latitude.toString());
    await services.settings.set(_centreLngKey, picked.longitude.toString());
    if (!mounted) return;
    setState(() => _centre = picked);
    if (_manId != null) await _loadRoutes(_manId!);
  }

  /// Asks for the centre. Prefilled from the saved point, or the middle of the
  /// map so the admin can simply pan to the shop and tap "Use map centre".
  Future<LatLng?> _pickCentre() async {
    final start = _centre ?? (_mapReady ? _map.camera.center : null);
    final lat = TextEditingController(
      text: start == null ? '' : start.latitude.toStringAsFixed(6),
    );
    final lng = TextEditingController(
      text: start == null ? '' : start.longitude.toStringAsFixed(6),
    );
    final picked = await showDialog<LatLng>(
      context: context,
      builder: (dialogCtx) {
        // Declared outside the StatefulBuilder so the error text survives a
        // rebuild instead of vanishing the moment it is shown.
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void save() {
              final la = double.tryParse(lat.text.trim());
              final lo = double.tryParse(lng.text.trim());
              if (!_isReal(la, lo)) {
                setDialogState(() {
                  error =
                      'Enter a latitude from -90 to 90 and a longitude '
                      'from -180 to 180.';
                });
                return;
              }
              Navigator.pop(dialogCtx, LatLng(la!, lo!));
            }

            void useMapCentre() {
              if (!_mapReady) {
                setDialogState(() => error = 'The map is not ready yet.');
                return;
              }
              final c = _map.camera.center;
              lat.text = c.latitude.toStringAsFixed(6);
              lng.text = c.longitude.toStringAsFixed(6);
              setDialogState(() => error = null);
            }

            return AlertDialog(
              title: const Text('Centre point'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The software\'s own location. Every distance on this '
                    'screen is measured from here.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  TextButton(
                    onPressed: useMapCentre,
                    child: const Text('Use map centre'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: save, child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    // Not disposed either — see _editRadius: disposing dialog controllers
    // here races the dialog's exit rebuild.
    return picked;
  }

  /// The meter limit: routes whose farthest point lies beyond it are flagged
  /// OVER. Kept in settings so it can be changed later without a rebuild.
  Future<void> _editRadius() async {
    final services = AppScope.of(context);
    final controller = TextEditingController(
      text: _radiusM == null ? '' : '${_radiusM!.round()}',
    );
    final saved = await showDialog<double>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void save() {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v.isNaN || v < 0) {
                setDialogState(() {
                  error = 'Enter a distance in meters, 0 or more.';
                });
                return;
              }
              Navigator.pop(dialogCtx, v);
            }

            return AlertDialog(
              title: const Text('Distance limit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A route is flagged OVER when its farthest point is more '
                    'than this from the centre point. Change it any time.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Meters from the centre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: save, child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    // Deliberately not disposed: while the route animates out the dialog's
    // field still rebuilds (cursor blink), and a disposed controller there
    // trips the ChangeNotifier assert. It is unreferenced once the route
    // subtree is gone and is collected then.
    if (saved == null || !mounted) return;
    await services.settings.set(_radiusKey, saved.toString());
    if (!mounted) return;
    setState(() => _radiusM = saved);
  }

  String _noRoutesMessage() {
    var name = '';
    for (final man in _men) {
      if (man.id == _manId) {
        name = man.name;
        break;
      }
    }
    return 'No routes were kept for ${name.isEmpty ? 'this delivery man' : name}.\n'
        'A route exists only for deliveries recorded while the companion app '
        'was sending GPS.';
  }

  static String _km(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(2)} km'
      : '${metres.round()} m';

  String _routeLabel(_Route route) {
    final analysis = route.analysis;
    final base = '${route.points.length} GPS point(s)';
    if (analysis == null) return base;
    return '$base · farthest ${_km(analysis.maxDistanceM)} from centre · '
        'average ${_km(analysis.meanDistanceM)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PageScaffold(
        title: 'Delivery Routes',
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return PageScaffold(
      title: 'Delivery Routes',
      actions: [
        IconButton(
          icon: const Icon(Icons.straighten),
          tooltip: 'Distance limit',
          onPressed: _editRadius,
        ),
        IconButton(
          icon: const Icon(Icons.place),
          tooltip: 'Set centre point',
          onPressed: _editCentre,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _load,
        ),
      ],
      body: _men.isEmpty
          ? const EmptyState(
              message:
                  'No delivery men yet.\nAdd one under Delivery Men '
                  'first.',
            )
          : Column(
              children: [
                _selector(),
                _farthestHeadline(),
                if (_selected != null) _analysisCard(_selected!),
                Expanded(flex: 3, child: _trackArea()),
                Expanded(flex: 2, child: _routesArea()),
              ],
            ),
    );
  }

  Widget _selector() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _men.any((m) => m.id == _manId) ? _manId : null,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Delivery man',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final man in _men)
                DropdownMenuItem(value: man.id, child: Text(man.name)),
            ],
            onChanged: (id) {
              if (id == null || id == _manId) return;
              setState(() {
                _manId = id;
                _routes = null;
                _selected = null;
              });
              _loadRoutes(id);
            },
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _editCentre,
          icon: const Icon(Icons.place, size: 18),
          label: Text(_centre == null ? 'Set centre' : 'Centre set'),
        ),
      ],
    ),
  );

  Widget _trackArea() {
    final routes = _routes;
    if (routes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final selected = _selected;
    if (selected == null) return EmptyState(message: _noRoutesMessage());
    return _mapFor(selected);
  }

  Widget _routesArea() {
    final routes = _routes;
    if (routes == null || routes.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        if (_centre != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Farthest from the centre first'
                '${_radiusM == null ? '' : ' · limit ${_km(_radiusM!)}'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: routes.length,
            itemBuilder: (ctx, i) {
              final route = routes[i];
              final isSelected = identical(route, _selected);
              final limit = _radiusM;
              final over =
                  limit != null &&
                  route.analysis != null &&
                  route.analysis!.maxDistanceM > limit;
              return ListTile(
                dense: true,
                selected: isSelected,
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: Colors.teal,
                ),
                title: Text(
                  '${route.commission.barcode} · '
                  '${fmtDate(route.commission.dateTime)}',
                ),
                subtitle: Text(_routeLabel(route)),
                trailing: over ? statusChip('OVER ${_km(limit)}') : null,
                onTap: () => _select(route),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The single farthest point across every route of the selected man, called
  /// out above the list so it is visible without reading the whole list.
  /// [_routes] is already sorted farthest-first whenever a centre is set.
  Widget _farthestHeadline() {
    final routes = _routes;
    if (routes == null || routes.isEmpty || _centre == null) {
      return const SizedBox.shrink();
    }
    final top = routes.first;
    final analysis = top.analysis;
    if (analysis == null) return const SizedBox.shrink();
    final limit = _radiusM;
    final over = limit != null && analysis.maxDistanceM > limit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: ListTile(
          dense: true,
          onTap: () => _select(top),
          leading: const Icon(Icons.my_location, color: Colors.red),
          title: Text(
            'Farthest point of all routes: ${_km(analysis.maxDistanceM)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          subtitle: Text(
            '${fmtDate(analysis.farthest.capturedAt)} · '
            'Receipt ${top.commission.barcode}',
          ),
          trailing: over ? statusChip('OVER ${_km(limit)}') : null,
        ),
      ),
    );
  }

  Widget _analysisCard(_Route route) {
    final analysis = route.analysis;
    final points = route.points;
    final gaps = routeSegments(points).length - 1;
    final rank = _routes == null ? 0 : _routes!.indexOf(route) + 1;
    final limit = _radiusM;
    final overLimit =
        limit != null && analysis != null && analysis.maxDistanceM > limit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Receipt ${route.commission.barcode}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${fmtDate(route.commission.dateTime)} · '
                '${fmtMMK(route.commission.commission)} · '
                '${points.length} GPS point(s)',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              if (analysis == null)
                const Text(
                  'Centre point not set — tap the pin above to measure how far '
                  'each route got.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                )
              else ...[
                Text(
                  'Farthest from centre: ${_km(analysis.maxDistanceM)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reached at ${fmtDate(analysis.farthest.capturedAt)} · '
                  'average ${_km(analysis.meanDistanceM)} from centre · '
                  'route #$rank of ${_routes?.length ?? 0} by distance',
                  style: const TextStyle(fontSize: 12),
                ),
                if (limit != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    overLimit
                        ? 'Over the ${_km(limit)} limit'
                        : 'Within the ${_km(limit)} limit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: overLimit ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ],
              if (gaps > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$gaps gap(s) in the route — GPS points are missing there '
                  'and no line is drawn across them.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'This shows where the phone was. It is not proof that a test '
                'was done, and it does not change the commission.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapFor(_Route route) {
    final centre = _centre;
    final points = route.points;
    final farthest = route.analysis?.farthest;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: LatLng(points.first.latitude, points.first.longitude),
        initialZoom: 15,
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
        PolylineLayer(
          polylines: [
            for (final segment in routeSegments(points))
              if (segment.length > 1)
                Polyline(
                  points: [
                    for (final p in segment) LatLng(p.latitude, p.longitude),
                  ],
                  strokeWidth: 4,
                  color: Colors.teal.shade600,
                ),
            // Centre to the farthest point: the measured distance itself.
            if (centre != null && farthest != null)
              Polyline(
                points: [centre, LatLng(farthest.latitude, farthest.longitude)],
                strokeWidth: 2,
                color: Colors.red.shade700,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < points.length; i++)
              _pointMarker(
                i,
                points[i],
                farthest: identical(points[i], farthest),
              ),
            if (centre != null)
              Marker(
                point: centre,
                width: 36,
                height: 36,
                child: const Tooltip(
                  message: 'Centre point',
                  child: Icon(Icons.place, size: 30, color: Colors.black87),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Marker _pointMarker(
    int index,
    DeliveryTripPoint point, {
    required bool farthest,
  }) {
    final centre = _centre;
    final fromCentre = centre == null
        ? null
        : const Distance()(centre, LatLng(point.latitude, point.longitude));
    final tooltip =
        '${index + 1} · ${fmtDate(point.capturedAt)}'
        '${fromCentre == null ? '' : ' · ${_km(fromCentre)} from centre'}';
    return Marker(
      point: LatLng(point.latitude, point.longitude),
      width: 32,
      height: 32,
      child: Tooltip(
        message: tooltip,
        child: CircleAvatar(
          radius: 14,
          backgroundColor: farthest ? Colors.red : Colors.teal,
          child: Text(
            '${index + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
