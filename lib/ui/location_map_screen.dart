import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import 'common.dart';

/// Admin: where each delivery man is, from the GPS fixes their companion app
/// forwards to the office while they are signed in.
class LocationMapScreen extends StatefulWidget {
  const LocationMapScreen({super.key});

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen> {
  /// The companion app captures about one fix a minute, so this asks often
  /// enough to look live without hammering the office database.
  static const Duration _refreshEvery = Duration(seconds: 30);

  final MapController _map = MapController();

  /// Newest fix per delivery man, keyed by delivery man id.
  final Map<String, DeliveryLocation> _latest = {};
  List<DeliveryMan> _men = [];
  bool _loading = true;
  bool _mapReady = false;
  bool _fitted = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.all();
    final latest = <String, DeliveryLocation>{};
    for (final man in men) {
      final fixes = await services.locations.forDeliveryMan(man.id, limit: 1);
      if (fixes.isNotEmpty) latest[man.id] = fixes.first;
    }
    if (!mounted) return;
    setState(() {
      _men = men;
      _latest
        ..clear()
        ..addAll(latest);
      _loading = false;
    });
    _fitOnce();
  }

  /// Frame the men the first time there is something to show. Later refreshes
  /// must not yank the map back while staff are panning it.
  void _fitOnce() {
    if (_fitted || !_mapReady || _latest.isEmpty) return;
    _fitted = true;
    final points = [
      for (final fix in _latest.values) LatLng(fix.latitude, fix.longitude),
    ];
    if (points.length == 1) {
      _map.move(points.first, 16);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  /// Fixes go stale; show it instead of presenting a dead pin as live.
  Color _ageColor(int capturedAt) {
    final minutes =
        (DateTime.now().millisecondsSinceEpoch - capturedAt) ~/ 60000;
    if (minutes < 15) return Colors.teal;
    return minutes < 60 ? Colors.orange : Colors.red;
  }

  String _initial(DeliveryMan man) => man.name.isEmpty ? '?' : man.name[0];

  void _showFix(DeliveryMan man, DeliveryLocation fix) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _ageColor(fix.capturedAt),
            child: Text(
              _initial(man),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(man.name),
          subtitle: Text(
            'Captured ${fmtDate(fix.capturedAt)}\n'
            '${fix.accuracyM == null ? 'Accuracy not reported' : 'Accurate to about ${fix.accuracyM!.round()} m'}'
            '${fix.barcode == null ? '' : '\nReceipt ${fix.barcode}'}',
          ),
          isThreeLine: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Delivery Map',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh now',
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(16.8661, 96.1951),
                    initialZoom: 12,
                    onMapReady: () {
                      _mapReady = true;
                      _fitOnce();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'lab_commission',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final man in _men)
                          if (_latest[man.id] != null)
                            _marker(man, _latest[man.id]!),
                      ],
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if (_latest.isEmpty)
                  Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _men.isEmpty
                              ? 'No delivery men yet.\n'
                                    'Add one under Delivery Men first.'
                              : 'No GPS fixes yet.\n'
                                    'A signed-in companion app sends one '
                                    'about every minute.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Marker _marker(DeliveryMan man, DeliveryLocation fix) => Marker(
    point: LatLng(fix.latitude, fix.longitude),
    width: 36,
    height: 36,
    child: GestureDetector(
      onTap: () => _showFix(man, fix),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: _ageColor(fix.capturedAt),
        child: Text(
          _initial(man),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ),
  );
}
