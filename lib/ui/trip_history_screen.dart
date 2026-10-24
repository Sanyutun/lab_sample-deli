import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/route_analysis.dart';
import 'common.dart';

/// The route kept for one delivered receipt: where the delivery man's phone was
/// in the 20 minutes before the office recorded the delivery.
///
/// The route is evidence of the phone's whereabouts only. It never decides
/// whether the delivery (or a test) happened, so the screen says what is
/// missing rather than filling the gaps in.
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({
    super.key,
    required this.barcode,
    required this.deliveryManName,
  });

  final String barcode;
  final String deliveryManName;

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  static const double _poorAccuracyM = 50;

  final MapController _map = MapController();
  List<DeliveryTripPoint>? _points;
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
    final points = await AppScope.of(context).trips
        .routeForBarcode(widget.barcode);
    if (!mounted) return;
    setState(() => _points = points);
    _fitOnce();
  }

  void _fitOnce() {
    final points = _points;
    if (_fitted || !_mapReady || points == null || points.isEmpty) return;
    _fitted = true;
    final coords = [for (final p in points) LatLng(p.latitude, p.longitude)];
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

  bool _poor(DeliveryTripPoint p) =>
      p.accuracyM == null || p.accuracyM! > _poorAccuracyM;

  /// Midpoints of the breaks between stretches: where the route is incomplete.
  List<LatLng> _gapPoints(List<List<DeliveryTripPoint>> segments) => [
    for (var i = 0; i + 1 < segments.length; i++)
      LatLng(
        (segments[i].last.latitude + segments[i + 1].first.latitude) / 2,
        (segments[i].last.longitude + segments[i + 1].first.longitude) / 2,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final points = _points;
    return PageScaffold(
      title: 'Trip History',
      body: points == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _summary(points),
                Expanded(
                  flex: 3,
                  child: points.isEmpty
                      ? const EmptyState(
                          message:
                              'No GPS points were kept for this receipt.\n'
                              'The phone may have had no fix, or was not '
                              'signed in.',
                        )
                      : FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: LatLng(
                              points.first.latitude,
                              points.first.longitude,
                            ),
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
                                        for (final p in segment)
                                          LatLng(p.latitude, p.longitude),
                                      ],
                                      strokeWidth: 4,
                                      color: Colors.teal.shade600,
                                    ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                for (var i = 0; i < points.length; i++)
                                  _pointMarker(i, points[i]),
                                for (final latLng in _gapPoints(
                                  routeSegments(points),
                                ))
                                  Marker(
                                    point: latLng,
                                    width: 30,
                                    height: 30,
                                    child: const Tooltip(
                                      message: 'GPS points missing here',
                                      child: Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  'OpenStreetMap contributors',
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                Expanded(flex: 2, child: _pointList(points)),
              ],
            ),
    );
  }

  Widget _summary(List<DeliveryTripPoint> points) {
    final segments = routeSegments(points);
    final gaps = segments.length - 1;
    final poor = points.where(_poor).length;
    const distance = Distance();
    var metres = 0.0;
    for (final segment in segments) {
      for (var i = 1; i < segment.length; i++) {
        metres += distance(
          LatLng(segment[i - 1].latitude, segment[i - 1].longitude),
          LatLng(segment[i].latitude, segment[i].longitude),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Receipt ${widget.barcode}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.deliveryManName} · ${points.length} point(s) · '
                '${(metres / 1000).toStringAsFixed(2)} km of route',
                style: const TextStyle(fontSize: 12),
              ),
              if (points.isEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'No route is available for this delivery.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
              if (gaps > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$gaps gap(s) in the route — GPS points are missing there '
                  'and no line is drawn across them.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
              if (poor > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$poor point(s) had poor or unreported accuracy '
                  '(> ${_poorAccuracyM.round()} m): treat the position with '
                  'care.',
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

  Widget _pointList(List<DeliveryTripPoint> points) {
    if (points.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: points.length,
      itemBuilder: (ctx, i) {
        final p = points[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: _poor(p) ? Colors.orange : Colors.teal,
            child: Text(
              '${i + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          title: Text(fmtDate(p.capturedAt)),
          subtitle: Text(_accuracyLabel(p.accuracyM)),
          onTap: () => _map.move(LatLng(p.latitude, p.longitude), 17),
        );
      },
    );
  }

  String _accuracyLabel(double? accuracyM) {
    if (accuracyM == null) return 'GPS accuracy not reported';
    final rounded = accuracyM.round();
    return rounded > _poorAccuracyM
        ? 'GPS accuracy ±$rounded m (poor)'
        : 'GPS accuracy ±$rounded m';
  }

  Marker _pointMarker(int index, DeliveryTripPoint point) => Marker(
    point: LatLng(point.latitude, point.longitude),
    width: 32,
    height: 32,
    child: Tooltip(
      message: '${index + 1} · ${fmtDate(point.capturedAt)}',
      child: CircleAvatar(
        radius: 14,
        backgroundColor: _poor(point) ? Colors.orange : Colors.teal,
        child: Text(
          '${index + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    ),
  );
}
