import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/companion/companion_api_server.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/route_analysis.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

Future<AppServices> _boot() => AppServices.bootstrap(MemoryStorage());

Future<String> _staffId(AppServices services) async =>
    (await services.users.all()).firstWhere((u) => !u.isAdmin).id;

/// A commission for [manId], recorded now.
Future<String> _deliver(
  AppServices services,
  String manId, {
  required String barcode,
}) async {
  final record = await services.delivery.recordCommission(
    barcode: barcode,
    deliveryManId: manId,
    commission: 1000,
    staffUserId: await _staffId(services),
  );
  return record.record.id;
}

void main() {
  group('Route segments', () {
    DeliveryTripPoint point(int at, double lat) => DeliveryTripPoint(
      id: 'p$at',
      barcode: 'B',
      commissionId: 'c',
      deliveryManId: 'm',
      latitude: lat,
      longitude: 96,
      capturedAt: at,
      createdAt: at,
    );

    test('a time gap splits the route so no line is drawn across it', () {
      final segments = routeSegments([
        point(0, 16.0),
        point(120000, 16.001),
        point(600000, 16.1), // 8 minutes later: the phone stopped reporting
        point(720000, 16.101),
      ]);
      expect(segments, hasLength(2));
      expect(segments.first, hasLength(2));
      expect(segments.last, hasLength(2));
    });

    test('a jump too far for a road leg splits the route too', () {
      final segments = routeSegments([
        point(0, 16.0),
        point(120000, 16.09), // ~10 km in one step: not a travelled leg
      ]);
      expect(segments, hasLength(2));
    });

    test('a tight, continuous track stays one segment', () {
      final segments = routeSegments([
        point(0, 16.8400),
        point(120000, 16.8405),
        point(240000, 16.8410),
      ]);
      expect(segments, hasLength(1));
    });
  });

  group('Preserved route for a delivery', () {
    test(
      'keeps only the 20 minutes before the delivery, linked to it',
      () async {
        final services = await _boot();
        final man = await services.deliveryMen.create(name: 'Ko Aung');
        final now = DateTime.now().millisecondsSinceEpoch;

        // Inside the window.
        await services.companion.recordLocation(
          man.id,
          latitude: 16.84,
          longitude: 96.17,
          accuracyM: 8,
          capturedAt: now - 30000,
        );
        // Outside it: 30 minutes before the delivery.
        await services.companion.recordLocation(
          man.id,
          latitude: 16.90,
          longitude: 96.20,
          capturedAt: now - 30 * 60 * 1000,
        );

        final commissionId = await _deliver(services, man.id, barcode: 'T1');
        final route = await services.trips.routeForBarcode('T1');
        expect(route, hasLength(1));
        expect(route.single.latitude, closeTo(16.84, 1e-9));
        expect(route.single.commissionId, commissionId);
        expect(route.single.barcode, 'T1');
        expect(route.single.deliveryManId, man.id);
      },
    );

    test('the route is ordered by the phone\'s capture time, not arrival', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;
      // Stored newest-first: the route must still start at the oldest capture.
      await services.companion.recordLocation(
        man.id,
        latitude: 16.86,
        longitude: 96.17,
        capturedAt: now - 60000,
      );
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
        capturedAt: now - 300000,
      );
      await services.companion.recordLocation(
        man.id,
        latitude: 16.85,
        longitude: 96.17,
        capturedAt: now - 180000,
      );

      await _deliver(services, man.id, barcode: 'T7');
      final route = await services.trips.routeForBarcode('T7');
      expect(route.map((p) => p.latitude), [16.84, 16.85, 16.86]);
    });

    test('another man\'s fixes are never attached to this route', () async {
      final services = await _boot();
      final aung = await services.deliveryMen.create(name: 'Ko Aung');
      final maung = await services.deliveryMen.create(name: 'Ko Maung');
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.companion.recordLocation(
        maung.id,
        latitude: 17.0,
        longitude: 96.5,
        capturedAt: now - 60000,
      );

      await _deliver(services, aung.id, barcode: 'T2');
      expect(await services.trips.routeForBarcode('T2'), isEmpty);
    });

    test('preserving twice does not duplicate the route', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
        capturedAt: now - 60000,
      );
      final commissionId = await _deliver(services, man.id, barcode: 'T3');
      final again = await services.trips.preserveForDelivery(
        barcode: 'T3',
        commissionId: commissionId,
        deliveryManId: man.id,
        verifiedAtMs: now,
      );
      expect(again, 0);
      expect(await services.trips.routeForBarcode('T3'), hasLength(1));
    });

    test('a fix arriving after the delivery still joins that route', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;

      // Delivery recorded while the man's phone was still offline: nothing to
      // copy yet.
      final commissionId = await _deliver(services, man.id, barcode: 'T5');
      expect(await services.trips.routeForBarcode('T5'), isEmpty);

      // The backlog arrives a moment later, carrying a fix captured before the
      // delivery.
      await services.companion.recordLocation(
        man.id,
        latitude: 16.85,
        longitude: 96.18,
        capturedAt: now - 60000,
        clientId: 'late-1',
      );

      final route = await services.trips.routeForBarcode('T5');
      expect(route, hasLength(1));
      expect(route.single.commissionId, commissionId);
      expect(route.single.sourceId, isNotNull);

      // Re-sending that fix never puts a second copy on the route.
      await services.companion.recordLocation(
        man.id,
        latitude: 16.85,
        longitude: 96.18,
        capturedAt: now - 60000,
        clientId: 'late-1',
      );
      await services.companion.recordLocation(
        man.id,
        latitude: 16.85,
        longitude: 96.18,
        capturedAt: now - 60000,
        clientId: 'late-1',
      );
      expect(await services.trips.routeForBarcode('T5'), hasLength(1));
    });

    test('fixes outside the 20 minutes are not attached', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;
      await _deliver(services, man.id, barcode: 'T6');

      // 21 minutes before the delivery: outside its window.
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
        capturedAt: now - 21 * 60 * 1000,
      );
      // After the delivery: this point belongs to no route of it.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await services.companion.recordLocation(
        man.id,
        latitude: 16.86,
        longitude: 96.19,
      );

      expect(await services.trips.routeForBarcode('T6'), isEmpty);
    });
  });

  group('Retention', () {
    test('old raw fixes are dropped, preserved routes survive', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
        capturedAt: now - 60000,
      );
      await _deliver(services, man.id, barcode: 'T4');

      // 30 minutes later only the preserved copy is left.
      final removed = await services.trips.purgeOldRawFixes(
        now: now + 30 * 60 * 1000,
      );
      expect(removed, 1);
      expect(await services.companion.listLocations(man.id), isEmpty);
      expect(await services.trips.routeForBarcode('T4'), hasLength(1));
    });

    test('a fix younger than the window is kept', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
      );
      final removed = await services.trips.purgeOldRawFixes();
      expect(removed, 0);
      expect(await services.companion.listLocations(man.id), hasLength(1));
    });
  });

  group('HTTP: trip history', () {
    late AppServices services;
    late CompanionApiServer server;
    late HttpClient client;
    late String base;

    setUp(() async {
      services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.companion.recordLocation(
        man.id,
        latitude: 16.84,
        longitude: 96.17,
        capturedAt: now - 60000,
      );
      await _deliver(services, man.id, barcode: 'H9');
      await services.companion.registerAccount(
        deliveryManId: man.id,
        loginId: 'aung',
        pin: '2468',
      );
      server = CompanionApiServer(service: services.companion, port: 0);
      await server.start();
      base = 'http://127.0.0.1:${server.boundPort}';
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<(int, Map<String, dynamic>)> call(
      String method,
      String url, {
      String? token,
      Object? body,
    }) async {
      final request = await client.openUrl(method, Uri.parse(url));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (
        response.statusCode,
        text.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(text) as Map<String, dynamic>,
      );
    }

    Future<String> login() async {
      final (status, body) = await call(
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      expect(status, 200);
      return body['token'] as String;
    }

    test('the man reads his own preserved route', () async {
      final token = await login();
      final (status, body) = await call(
        'GET',
        '$base${ApiRoutes.trip('H9')}',
        token: token,
      );
      expect(status, 200);
      final trip = TripHistoryDto.fromJson(body);
      expect(trip.barcode, 'H9');
      expect(trip.points, hasLength(1));
      expect(trip.points.single.latitude, closeTo(16.84, 1e-9));
    });

    test('a barcode that is not his answers 404, not data', () async {
      final other = await services.deliveryMen.create(name: 'Ko Other');
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.companion.recordLocation(
        other.id,
        latitude: 17,
        longitude: 96.5,
        capturedAt: now - 60000,
      );
      await _deliver(services, other.id, barcode: 'NOT-MINE');

      final token = await login();
      final (status, _) = await call(
        'GET',
        '$base${ApiRoutes.trip('NOT-MINE')}',
        token: token,
      );
      expect(status, 404);
    });

    test('no token means no trip', () async {
      final (status, _) = await call('GET', '$base${ApiRoutes.trip('H9')}');
      expect(status, 401);
    });
  });
}
