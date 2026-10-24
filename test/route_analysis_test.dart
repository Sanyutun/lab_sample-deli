import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/domain/route_analysis.dart';
import 'package:latlong2/latlong.dart';

DeliveryTripPoint point(String id, double lat, double lng, {int at = 0}) =>
    DeliveryTripPoint(
      id: id,
      barcode: 'B',
      commissionId: 'c',
      deliveryManId: 'm',
      latitude: lat,
      longitude: lng,
      capturedAt: at,
      createdAt: at,
    );

void main() {
  const centre = LatLng(16.80, 96.20);

  test('an empty route has nothing to measure', () {
    expect(analyzeRoute(const <DeliveryTripPoint>[], centre), isNull);
  });

  test('measures from the centre, not from the route\'s own first point', () {
    // The nearer point is listed first, so a distance measured from the route
    // itself would wrongly call the last point the farthest.
    final near = point('a', 16.8005, 96.2005, at: 0);
    final far = point('b', 16.81, 96.21, at: 60000);
    final analysis = analyzeRoute([near, far], centre)!;

    const distance = Distance();
    expect(analysis.farthest.id, 'b');
    expect(
      analysis.maxDistanceM,
      closeTo(distance(centre, LatLng(far.latitude, far.longitude)), 0.001),
    );
    // The mean tells a route that stayed far from one that only spiked.
    expect(analysis.maxDistanceM, greaterThan(analysis.meanDistanceM));
  });

  test('the order of the points does not change the answer', () {
    final points = [
      point('a', 16.8005, 96.2005),
      point('b', 16.81, 96.21),
      point('c', 16.803, 96.202),
    ];
    final forwards = analyzeRoute(points, centre)!;
    final backwards = analyzeRoute(points.reversed.toList(), centre)!;

    expect(backwards.farthest.id, forwards.farthest.id);
    expect(backwards.maxDistanceM, closeTo(forwards.maxDistanceM, 0.001));
    expect(backwards.meanDistanceM, closeTo(forwards.meanDistanceM, 0.001));
  });
}
