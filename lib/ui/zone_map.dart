import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../domain/route_analysis.dart';

/// A zone's colour as displayed on the map and in the summary bars.
Color zoneColor(DistanceZone zone) => Color(zone.argb);

/// The zone rings around the office centre — a translucent fill in the zone's
/// colour up to its outer boundary, plus a small label on each ring. The
/// open-ended zone has no ring to draw. Spread these into a [FlutterMap]'s
/// children *before* the route lines so they never hide them.
List<Widget> zoneLayers({
  required LatLng centre,
  required List<DistanceZone> zones,
}) {
  final rings =
      [
        for (final zone in enabledZones(zones))
          if (zone.maxKm != null) zone,
      ]..sort(
        (a, b) => b.maxKm!.compareTo(a.maxKm!),
      ); // biggest first: painted under
  return [
    CircleLayer(
      circles: [
        for (final zone in rings)
          CircleMarker(
            point: centre,
            radius: zone.maxKm! * 1000,
            useRadiusInMeter: true,
            color: zoneColor(zone).withValues(alpha: 0.08),
            borderColor: zoneColor(zone),
            borderStrokeWidth: 2,
          ),
      ],
    ),
    MarkerLayer(
      markers: [
        for (final zone in rings)
          Marker(
            // The ring's northern edge, where a label is out of the route's way.
            point: LatLng(
              centre.latitude + zone.maxKm! / 111.32,
              centre.longitude,
            ),
            width: 140,
            height: 20,
            child: Text(
              // The ring's own distance, not the zone's whole band: it is
              // what the circle is actually drawn at.
              '${zone.name} · ${trimKm(zone.maxKm!)} km',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: zoneColor(zone),
                shadows: const [Shadow(blurRadius: 3, color: Colors.white)],
              ),
            ),
          ),
      ],
    ),
  ];
}
