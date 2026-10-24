import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/companion/companion_api_server.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/exceptions.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

Future<AppServices> _boot() => AppServices.bootstrap(MemoryStorage());

/// Records one commission for [manId] and returns the created record.
Future<CommissionRecord> _deliver(
  AppServices services,
  String manId, {
  required String barcode,
  int commission = 1000,
}) async {
  final staff = (await services.users.all()).firstWhere((u) => !u.isAdmin);
  final result = await services.delivery.recordCommission(
    barcode: barcode,
    deliveryManId: manId,
    commission: commission,
    staffUserId: staff.id,
  );
  return result.record;
}

Future<String> _staffId(AppServices services) async =>
    (await services.users.all()).firstWhere((u) => !u.isAdmin).id;

/// (status, decoded body) for one HTTP call against the sync server.
Future<(int, Map<String, dynamic>)> _call(
  HttpClient client,
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
  final decoded = text.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(text) as Map<String, dynamic>;
  return (response.statusCode, decoded);
}

void main() {
  group('Companion accounts & authentication', () {
    test('register requires a sane login id and PIN', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');

      expect(
        () => services.companion.registerAccount(
          deliveryManId: man.id,
          loginId: 'ab',
          pin: '1234',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => services.companion.registerAccount(
          deliveryManId: man.id,
          loginId: 'aung',
          pin: '12',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('login rejects a wrong PIN and accepts the right one', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      await services.companion.registerAccount(
        deliveryManId: man.id,
        loginId: 'aung',
        pin: '2468',
      );

      expect(
        () => services.companion.login(loginId: 'aung', pin: '0000'),
        throwsA(isA<ValidationException>()),
      );
      final session = await services.companion.login(
        loginId: 'aung',
        pin: '2468',
      );
      expect(session.profile.id, man.id);
      expect(session.token, isNotEmpty);
      expect(
        session.expiresAt,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
    });

    test('a revoked session stops working', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      await services.companion.registerAccount(
        deliveryManId: man.id,
        loginId: 'aung',
        pin: '2468',
      );
      final session = await services.companion.login(
        loginId: 'aung',
        pin: '2468',
      );
      expect(await services.companion.authenticate(session.token), isNotNull);

      await services.companion.logout(session.token);
      expect(
        () => services.companion.authenticate(session.token),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('deactivating an account blocks new sessions', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final account = await services.companion.registerAccount(
        deliveryManId: man.id,
        loginId: 'aung',
        pin: '2468',
      );
      await services.companion.setActive(account.id, false);

      expect(
        () => services.companion.login(loginId: 'aung', pin: '2468'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('Per-delivery-man isolation', () {
    test('one delivery man never sees another\'s records or totals', () async {
      final services = await _boot();
      final a = await services.deliveryMen.create(name: 'Aung');
      final b = await services.deliveryMen.create(name: 'Bala');
      final recA = await _deliver(services, a.id, barcode: 'A1');
      await _deliver(services, b.id, barcode: 'B1', commission: 3000);

      final summaryA = await services.companion.summary(a.id);
      expect(summaryA.successfulDeliveries, 1);
      expect(summaryA.commissionEarned, 1000);

      final listA = await services.companion.listCommissions(a.id);
      expect(listA.map((c) => c.barcode), ['A1']);

      // Directly asking for B's record with A's identity returns nothing.
      final bRecord = (await services.commissions.all(deliveryManId: b.id))
          .first;
      expect(
        await services.companion.commissionDetail(a.id, bRecord.id),
        isNull,
      );
      expect(
        await services.companion.commissionDetail(b.id, bRecord.id),
        isNotNull,
      );
      expect(
        await services.companion.commissionDetail(a.id, recA.id),
        isNotNull,
      );
    });
  });

  group('Delivery board (own records only)', () {
    test('numbers deliveries and marks the 10-delivery milestone', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      for (var i = 1; i <= 10; i++) {
        await _deliver(services, man.id, barcode: 'BD$i');
      }

      final board = await services.companion.deliveryBoard(man.id);
      // Only groups holding a delivery are sent; positions/numbering are not
      // trimmed, so the total is still 2000.
      expect(board.groups, hasLength(1));
      expect(board.totalSlots, 2000);
      expect(board.summary.successfulDeliveries, 10);
      expect(board.summary.commissionEarned, 10000);

      final first = board.groups.single;
      expect(first.groupNumber, 1);
      expect(first.slots, hasLength(10));
      expect(first.successfulCount, 10);
      expect(first.slots.every((s) => s.state == 'successful'), isTrue);
      expect(first.slots.map((s) => s.barcode).toSet(), {
        'BD1',
        'BD2',
        'BD3',
        'BD4',
        'BD5',
        'BD6',
        'BD7',
        'BD8',
        'BD9',
        'BD10',
      });
      expect(first.milestoneAmounts, [4000]);
      expect(first.slots.last.milestoneAmount, 4000);
    });

    test(
      'one delivery man\'s board never shows another\'s deliveries',
      () async {
        final services = await _boot();
        final a = await services.deliveryMen.create(name: 'Aung');
        final b = await services.deliveryMen.create(name: 'Bala');
        await _deliver(services, a.id, barcode: 'A1');
        await _deliver(services, b.id, barcode: 'B1', commission: 3000);

        final boardA = await services.companion.deliveryBoard(a.id);
        expect(boardA.summary.successfulDeliveries, 1);
        expect(boardA.summary.commissionEarned, 1000);
        // One delivery means one group is sent, not the other man's.
        expect(boardA.groups, hasLength(1));
        final filled = boardA.groups
            .expand((g) => g.slots)
            .where((s) => !s.isEmpty)
            .toList();
        expect(filled.map((s) => s.barcode), ['A1']);
      },
    );
  });

  group('QR identity', () {
    test('rotate issues an opaque payload the office can verify', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(
        name: 'Ko Aung',
        phone: '09991234567',
      );
      final account = await services.companion.registerAccount(
        deliveryManId: man.id,
        loginId: 'aung',
        pin: '2468',
      );

      final qr = await services.companion.rotateQr(account.id);
      final token = tokenFromQrPayload(qr.payload)!;
      final verified = await services.companion.verifyQr(token);
      expect(verified!.id, man.id);
      // The payload must not leak personal or financial data.
      expect(qr.payload.contains(man.name), isFalse);
      expect(qr.payload, isNot(contains(man.phone)));

      // A random/garbage token is refused.
      expect(await services.companion.verifyQr(randomToken()), isNull);
    });

    test(
      'rotating invalidates the previous code and revoke kills the current',
      () async {
        final services = await _boot();
        final man = await services.deliveryMen.create(name: 'Ko Aung');
        final account = await services.companion.registerAccount(
          deliveryManId: man.id,
          loginId: 'aung',
          pin: '2468',
        );

        final first = tokenFromQrPayload(
          (await services.companion.rotateQr(account.id)).payload,
        )!;
        final second = tokenFromQrPayload(
          (await services.companion.rotateQr(account.id)).payload,
        )!;
        expect(await services.companion.verifyQr(first), isNull);
        expect(await services.companion.verifyQr(second), isNotNull);

        await services.companion.revokeQr(account.id);
        expect(await services.companion.verifyQr(second), isNull);
      },
    );
  });

  group('Totals from authoritative transactions', () {
    test('earned, paid and unpaid commission are distinct', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final staffId = await _staffId(services);
      final r1 = await _deliver(services, man.id, barcode: 'S1');
      await _deliver(services, man.id, barcode: 'S2', commission: 2000);
      await services.delivery.markPaid(recordId: r1.id, staffUserId: staffId);

      final s = await services.companion.summary(man.id);
      expect(s.successfulDeliveries, 2);
      expect(s.commissionEarned, 3000);
      expect(s.commissionPaid, 1000);
      expect(s.unpaidCommission, 2000);

      final detail = await services.companion.commissionDetail(man.id, r1.id);
      expect(detail!.isPaid, isTrue);
      expect(detail.payments, hasLength(1));
      expect(detail.payments.single.amount, -1000);
    });

    test('the 10th delivery earns one 4,000 MMK reward', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      for (var i = 1; i <= 10; i++) {
        await _deliver(services, man.id, barcode: 'M$i');
      }

      final rewards = await services.companion.listRewards(man.id);
      expect(rewards, hasLength(1));
      expect(rewards.single.everyN, 10);
      expect(rewards.single.rewardAmount, 4000);

      final s = await services.companion.summary(man.id);
      expect(s.rewardsEarned, 4000);
      expect(s.rewardsPaid, 0);
      expect(s.unpaidRewards, 4000);
    });

    test('date and payment filters narrow the list', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final staffId = await _staffId(services);
      final r1 = await _deliver(services, man.id, barcode: 'F1');
      await _deliver(services, man.id, barcode: 'F2');
      await services.delivery.markPaid(recordId: r1.id, staffUserId: staffId);

      final paid = await services.companion.listCommissions(
        man.id,
        paymentStatus: 'paid',
      );
      expect(paid.map((c) => c.barcode), ['F1']);

      final unpaid = await services.companion.listCommissions(
        man.id,
        paymentStatus: 'unpaid',
      );
      expect(unpaid.map((c) => c.barcode), ['F2']);

      final none = await services.companion.listCommissions(
        man.id,
        from: '2999-01-01',
        to: '2999-12-31',
      );
      expect(none, isEmpty);
    });
  });

  group('GPS records', () {
    test(
      'a fix is stored against the authenticated man and validated',
      () async {
        final services = await _boot();
        final man = await services.deliveryMen.create(name: 'Ko Aung');

        final point = await services.companion.recordLocation(
          man.id,
          latitude: 16.8409,
          longitude: 96.1735,
          accuracyM: 7.5,
          barcode: 'G1',
        );
        expect(point.accuracyM, 7.5);
        expect(point.barcode, 'G1');

        final list = await services.companion.listLocations(man.id);
        expect(list, hasLength(1));
        expect(list.single.latitude, closeTo(16.8409, 1e-9));

        expect(
          () => services.companion.recordLocation(
            man.id,
            latitude: 200,
            longitude: 96,
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('a future device timestamp is clamped, never trusted', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final future = DateTime.now().millisecondsSinceEpoch + 600000;
      final point = await services.companion.recordLocation(
        man.id,
        latitude: 16,
        longitude: 96,
        capturedAt: future,
      );
      expect(
        point.capturedAt,
        lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
      );
    });

    test('re-uploading a fix the phone already sent stores it once', () async {
      final services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');

      final first = await services.companion.recordLocation(
        man.id,
        latitude: 16.8,
        longitude: 96.1,
        clientId: 'phone-1',
      );
      final second = await services.companion.recordLocation(
        man.id,
        latitude: 16.8,
        longitude: 96.1,
        clientId: 'phone-1',
      );

      expect(second.id, first.id);
      expect(await services.companion.listLocations(man.id), hasLength(1));
    });
  });

  group('GPS policy (office-admin controlled)', () {
    test(
      'defaults to the standard policy and round-trips a saved one',
      () async {
        final services = await _boot();
        final initial = await services.companion.gpsPolicy();
        expect(initial.intervalMinutes, 2);
        expect(initial.retentionMinutes, GpsPolicyDto.threeDaysMinutes);

        await services.companion.saveGpsPolicy(
          const GpsPolicyDto(intervalMinutes: 5, retentionMinutes: 30),
        );

        final saved = await services.companion.gpsPolicy();
        expect(saved.intervalMinutes, 5);
        expect(saved.retentionMinutes, 30);
      },
    );

    test('a value outside the shared presets is refused', () async {
      final services = await _boot();
      expect(
        () => services.companion.saveGpsPolicy(
          const GpsPolicyDto(intervalMinutes: 3, retentionMinutes: 20),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('HTTP server: authorization & read-only surface', () {
    late AppServices services;
    late CompanionApiServer server;
    late HttpClient client;
    late String base;
    late String manId;

    setUp(() async {
      services = await _boot();
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      manId = man.id;
      await _deliver(services, man.id, barcode: 'H1');
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

    test('login then read own summary', () async {
      final (loginStatus, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      expect(loginStatus, 200);
      final token = login['token'] as String;

      final (status, summary) = await _call(
        client,
        'GET',
        '$base${ApiRoutes.summary}',
        token: token,
      );
      expect(status, 200);
      expect(summary['successfulDeliveries'], 1);
      expect(summary['commissionEarned'], 1000);
    });

    test('the GPS policy is served to a signed-in phone', () async {
      final (_, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      final token = login['token'] as String;

      final (status, policy) = await _call(
        client,
        'GET',
        '$base${ApiRoutes.gpsPolicy}',
        token: token,
      );
      expect(status, 200);
      expect(policy['intervalMinutes'], 2);
      expect(policy['retentionMinutes'], GpsPolicyDto.threeDaysMinutes);
    });

    test('the delivery board is served for the session owner', () async {
      final (_, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      final token = login['token'] as String;

      final (status, board) = await _call(
        client,
        'GET',
        '$base${ApiRoutes.deliveryBoard}',
        token: token,
      );
      expect(status, 200);
      expect(board['totalSlots'], 2000);
      expect(board['groups'] as List, hasLength(1));
      expect((board['summary'] as Map)['successfulDeliveries'], 1);
    });

    test('no token means no data', () async {
      final (status, body) = await _call(
        client,
        'GET',
        '$base${ApiRoutes.summary}',
      );
      expect(status, 401);
      expect((body['error'] as Map)['code'], 'unauthorized');
    });

    test('there is no way to write a commission or reward', () async {
      final (_, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      final token = login['token'] as String;

      for (final path in [ApiRoutes.commissions, ApiRoutes.rewards]) {
        final (status, _) = await _call(
          client,
          'POST',
          '$base$path',
          token: token,
          body: {'commission': 999999},
        );
        expect(status, 404, reason: 'POST $path must not exist');
      }
    });

    test('a subject id in the path cannot cross to another man', () async {
      final other = await services.deliveryMen.create(name: 'Bala');
      final otherRecord = await _deliver(services, other.id, barcode: 'X1');

      final (_, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      final token = login['token'] as String;

      final (status, _) = await _call(
        client,
        'GET',
        '$base${ApiRoutes.commission(otherRecord.id)}',
        token: token,
      );
      expect(status, 404);
    });

    test('GPS is filed against the session owner, not a body field', () async {
      final (_, login) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.login}',
        body: {'loginId': 'aung', 'pin': '2468'},
      );
      final token = login['token'] as String;

      final (status, _) = await _call(
        client,
        'POST',
        '$base${ApiRoutes.locations}',
        token: token,
        body: {
          'latitude': 16.8,
          'longitude': 96.1,
          'accuracyM': 6.0,
          // A malicious client trying to file against someone else is ignored.
          'deliveryManId': 'someone-else',
        },
      );
      expect(status, 201);
      final stored = await services.companion.listLocations(manId);
      expect(stored, hasLength(1));
      expect(stored.single.latitude, 16.8);
    });

    test(
      're-sending a fix with the same clientId does not duplicate it',
      () async {
        final (_, login) = await _call(
          client,
          'POST',
          '$base${ApiRoutes.login}',
          body: {'loginId': 'aung', 'pin': '2468'},
        );
        final token = login['token'] as String;

        final (firstStatus, first) = await _call(
          client,
          'POST',
          '$base${ApiRoutes.locations}',
          token: token,
          body: {'latitude': 16.8, 'longitude': 96.1, 'clientId': 'phone-9'},
        );
        final (secondStatus, second) = await _call(
          client,
          'POST',
          '$base${ApiRoutes.locations}',
          token: token,
          body: {'latitude': 16.8, 'longitude': 96.1, 'clientId': 'phone-9'},
        );

        expect(firstStatus, 201);
        expect(secondStatus, 201);
        expect(second['id'], first['id']);
        expect(await services.companion.listLocations(manId), hasLength(1));
      },
    );
  });

  group('sync server lifetime', () {
    test('a server left on comes back up on the next launch', () async {
      final storage = MemoryStorage();
      final first = await AppServices.bootstrap(storage, companionPort: 0);
      expect(first.companionServerRunning, isFalse);

      await first.setCompanionServerEnabled(true);
      expect(first.companionServerRunning, isTrue);

      // Same database, fresh launch: it starts again without a tap.
      final relaunched = await AppServices.bootstrap(storage, companionPort: 0);
      expect(relaunched.companionServerRunning, isTrue);

      await first.setCompanionServerEnabled(false);
      await relaunched.setCompanionServerEnabled(false);
    });
  });
}
