import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:lab_delivery_companion/core/app_services.dart';
import 'package:lab_delivery_companion/core/failure.dart';
import 'package:lab_delivery_companion/core/strings.dart';
import 'package:lab_delivery_companion/data/api/http_companion_api.dart';
import 'package:lab_delivery_companion/data/services/location_service.dart';
import 'package:lab_delivery_companion/data/storage/location_queue.dart';
import 'package:lab_delivery_companion/ui/screens/delivery_board_screen.dart';
import 'package:lab_delivery_companion/ui/screens/location_screen.dart';
import 'package:lab_delivery_companion/ui/screens/qr_screen.dart';

import 'support/fakes.dart';

/// A board with one filled position (barcode B1) in group 1.
DeliveryBoardDto _board() => const DeliveryBoardDto(
  summary: BoardSummaryDto(
    successfulDeliveries: 1,
    totalSlots: 2000,
    commissionEarned: 1000,
    commissionPaid: 0,
    unpaidCommission: 1000,
    rewardsEarned: 0,
    rewardsPaid: 0,
    unpaidBalance: 1000,
  ),
  slotsPerGroup: 10,
  totalSlots: 2000,
  groups: [
    BoardGroupDto(
      groupNumber: 1,
      startNumber: 1,
      endNumber: 10,
      successfulCount: 1,
      commissionTotal: 1000,
      milestoneAmounts: [],
      slots: [
        BoardSlotDto(
          number: 1,
          state: 'successful',
          commission: 1000,
          barcode: 'B1',
          recordedAt: 1,
          reconciliationStatus: 'match',
        ),
        BoardSlotDto(number: 2, state: 'empty'),
        BoardSlotDto(number: 3, state: 'empty'),
        BoardSlotDto(number: 4, state: 'empty'),
        BoardSlotDto(number: 5, state: 'empty'),
        BoardSlotDto(number: 6, state: 'empty'),
        BoardSlotDto(number: 7, state: 'empty'),
        BoardSlotDto(number: 8, state: 'empty'),
        BoardSlotDto(number: 9, state: 'empty'),
        BoardSlotDto(number: 10, state: 'empty'),
      ],
    ),
  ],
);

const _summary = SummaryDto(
  successfulDeliveries: 2,
  commissionEarned: 3000,
  commissionPaid: 1000,
  unpaidCommission: 2000,
  rewardsEarned: 4000,
  rewardsPaid: 4000,
  unpaidRewards: 0,
);

Future<void> _pumpTab(WidgetTester tester, TestHarness h, Widget child) async {
  await tester.pumpWidget(
    AppScope(
      services: h.services,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Authentication & isolation', () {
    test(
      'login keeps the token out of the profile and in secure storage',
      () async {
        final h = TestHarness();
        await h.auth.login(loginId: 'aung', pin: '2468');

        expect(h.auth.isLoggedIn, isTrue);
        expect(h.api.token, 'session-token');
        expect(await h.sessions.readToken(), 'session-token');
        expect(h.auth.profile!.id, 'm1');
      },
    );

    test('a revoked token signs the user out and clears the session', () async {
      final h = TestHarness();
      await h.sessions.writeToken('stale-token');
      h.api.failure = const UnauthorizedFailure();

      await h.auth.restore();

      expect(h.auth.isLoggedIn, isFalse);
      expect(h.api.token, isNull);
      expect(await h.sessions.readToken(), isNull);
    });

    test('an unauthorized read is never served from the cache', () async {
      final h = TestHarness();
      h.api.failure = const UnauthorizedFailure();

      await expectLater(
        h.repository.profile(),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(await h.cache.read('profile'), isNull);
    });

    test('offline launch reuses the last synced profile', () async {
      final h = TestHarness();
      await h.sessions.writeToken('token');
      await h.auth.restore(); // online: fills the profile cache
      expect(h.auth.isLoggedIn, isTrue);

      h.api.failure = const OfflineFailure();
      await h.auth.restore();

      expect(
        h.auth.isLoggedIn,
        isTrue,
        reason: 'cached profile keeps app open',
      );
      expect(h.auth.profile!.id, 'm1');
    });
  });

  group('QR identity', () {
    test('the payload is cached so it can be shown offline', () async {
      final h = TestHarness();
      h.api.qrValue = const QrIdentityDto(payload: 'lc1:opaque', issuedAt: 5);

      final online = await h.repository.qr();
      expect(online.value.payload, 'lc1:opaque');
      expect(online.stale, isFalse);

      h.api.failure = const OfflineFailure();
      final offline = await h.repository.qr();
      expect(offline.stale, isTrue);
      expect(offline.value.payload, 'lc1:opaque');
    });
  });

  group('Server-authoritative figures', () {
    test(
      'the dashboard shows the summary the server sent, unchanged',
      () async {
        final h = TestHarness();
        h.api.summaryValue = _summary;

        final result = await h.repository.summary();

        expect(result.value.successfulDeliveries, 2);
        expect(result.value.commissionEarned, 3000);
        expect(result.value.unpaidCommission, 2000);
        expect(result.value.rewardsEarned, 4000);
        expect(result.value.rewardsPaid, 4000);
        expect(result.value.unpaidRewards, 0);
      },
    );

    test('date and payment filters are forwarded to the office', () async {
      final h = TestHarness();

      await h.repository.commissions(
        from: '2026-01-01',
        to: '2026-01-31',
        status: 'unpaid',
      );

      expect(h.api.calls, contains('commissions:2026-01-01:2026-01-31:unpaid'));
    });

    test('a commission detail carries its payment history', () async {
      final h = TestHarness();
      h.api.commissionValue = const CommissionDto(
        id: 'r1',
        barcode: 'B1',
        commission: 1500,
        dateTime: 1,
        paymentStatus: 'paid',
        reconciliationStatus: 'match',
        payments: [
          PaymentEntryDto(
            type: 'commissionPayment',
            amount: -1500,
            date: '2026-01-02',
          ),
        ],
      );

      final detail = await h.repository.commission('r1');

      expect(detail.value.isPaid, isTrue);
      expect(detail.value.payments.single.amount, -1500);
    });

    test(
      'the delivery board round-trips and is served from cache offline',
      () async {
        final h = TestHarness();
        h.api.deliveryBoardValue = _board();

        final online = await h.repository.deliveryBoard();
        expect(online.stale, isFalse);
        expect(online.value.totalSlots, 2000);
        expect(online.value.groups.single.slots.first.barcode, 'B1');

        h.api.failure = const OfflineFailure();
        final offline = await h.repository.deliveryBoard();
        expect(offline.stale, isTrue);
        expect(offline.value.groups.single.slots.first.barcode, 'B1');
      },
    );
  });

  group('Failed synchronization', () {
    test('a stale summary is served from cache with its timestamp', () async {
      final h = TestHarness();
      h.api.summaryValue = _summary;
      await h.repository.summary(); // fill the cache

      h.api.failure = const OfflineFailure();
      final result = await h.repository.summary();

      expect(result.stale, isTrue);
      expect(result.value.commissionEarned, 3000);
      expect(result.cachedAt, isNotNull);
    });

    test('with nothing cached, an offline read fails loudly', () async {
      final h = TestHarness();
      h.api.failure = const OfflineFailure();

      await expectLater(h.repository.summary(), throwsA(isA<OfflineFailure>()));
    });
  });

  group('Background tracking & forwarding', () {
    // Captured "now", so it is inside the 20-minute window the phone keeps
    // sent fixes for.
    final fix = Fix(
      latitude: 16.8409,
      longitude: 96.1735,
      capturedAt: DateTime.now().millisecondsSinceEpoch,
      accuracyM: 7.5,
    );

    test('a stream fix is queued, forwarded, then marked sent', () async {
      final h = TestHarness();
      addTearDown(() => h.tracking.onSignedInChanged(false));
      await h.tracking.onSignedInChanged(true);
      expect(h.tracking.streaming, isTrue);
      // The ongoing notification is how the user is told tracking is on.
      expect(h.location.notificationRequests, 1);

      h.location.emit(fix);
      await pumpEventQueue();

      expect(h.api.recordedLocations, hasLength(1));
      expect(h.api.recordedLocations.single.clientId, isNotNull);
      expect(h.tracking.pending, 0);
      expect((await h.queue.recent()).single.transferred, isTrue);
    });

    test(
      'an offline fix waits in the queue and sends once back online',
      () async {
        final h = TestHarness();
        addTearDown(() => h.tracking.onSignedInChanged(false));
        h.api.failure = const OfflineFailure();
        await h.tracking.onSignedInChanged(true);

        h.location.emit(fix);
        await pumpEventQueue();

        expect(h.api.recordedLocations, isEmpty);
        expect(h.tracking.pending, 1);
        expect((await h.queue.recent()).single.transferred, isFalse);

        h.api.failure = null;
        await h.tracking.syncNow();

        expect(h.api.recordedLocations, hasLength(1));
        expect(h.tracking.pending, 0);
      },
    );

    test('denied permission keeps the stream off and explains why', () async {
      final h = TestHarness(
        location: FakeLocationService(access: LocationAccess.denied),
      );
      await h.tracking.onSignedInChanged(true);

      expect(h.tracking.streaming, isFalse);
      expect(h.tracking.note, S.trackDenied);
      expect(h.api.calls, isNot(contains('recordLocation')));
      // No stream means no ongoing notification to ask about.
      expect(h.location.notificationRequests, 0);
    });

    test(
      'the office policy sets the capture interval and pure retention',
      () async {
        final h = TestHarness();
        addTearDown(() => h.tracking.onSignedInChanged(false));
        h.api.gpsPolicyValue = const GpsPolicyDto(
          intervalMinutes: 5,
          retentionMinutes: 10,
        );

        await h.tracking.onSignedInChanged(true);

        expect(h.location.requestedInterval, const Duration(minutes: 5));
        expect(h.tracking.retention, const Duration(minutes: 10));
        // A sent fix older than the office's 10-minute window is dropped.
        final old = DateTime.now()
            .subtract(const Duration(minutes: 15))
            .millisecondsSinceEpoch;
        await h.queue.add(
          QueuedFix(
            id: 'old',
            latitude: 16.84,
            longitude: 96.17,
            capturedAt: old,
          ),
        );
        await h.queue.markTransferred(['old']);
        await h.tracking.syncNow();
        expect(await h.queue.recent(), isEmpty);
      },
    );

    test('offline at start keeps the standard policy', () async {
      final h = TestHarness();
      addTearDown(() => h.tracking.onSignedInChanged(false));
      h.api.failure = const OfflineFailure();

      await h.tracking.onSignedInChanged(true);

      expect(h.location.requestedInterval, const Duration(minutes: 2));
      expect(h.tracking.retention, GpsPolicyDto.standard.retention);
    });

    test(
      'sign-out clears the backlog so a fix cannot be misattributed',
      () async {
        final h = TestHarness();
        h.api.failure = const OfflineFailure();
        await h.tracking.onSignedInChanged(true);

        h.location.emit(fix);
        await pumpEventQueue();
        expect(h.tracking.pending, 1);

        await h.tracking.onSignedInChanged(false);

        expect(await h.queue.pending(), isEmpty);
        expect(h.tracking.pending, 0);
        expect(h.tracking.streaming, isFalse);
      },
    );

    test(
      'an unsent fix older than the window is kept for the office',
      () async {
        final h = TestHarness();
        h.api.failure = const OfflineFailure();
        final old = DateTime.now()
            .subtract(const Duration(days: 4))
            .millisecondsSinceEpoch;
        await h.queue.add(
          QueuedFix(
            id: 'stale',
            latitude: 16.84,
            longitude: 96.17,
            capturedAt: old,
          ),
        );

        await h.tracking.syncNow();

        // Retention never touches what the office has not acknowledged yet.
        expect((await h.queue.recent()).single.id, 'stale');
        expect(h.tracking.pending, 1);
      },
    );

    test(
      'a sent fix past the three-day window is dropped from the phone',
      () async {
        final h = TestHarness();
        final old = DateTime.now()
            .subtract(const Duration(days: 4))
            .millisecondsSinceEpoch;
        await h.queue.add(
          QueuedFix(
            id: 'old',
            latitude: 16.84,
            longitude: 96.17,
            capturedAt: old,
          ),
        );
        await h.queue.markTransferred(['old']);

        await h.tracking.syncNow();

        expect(await h.queue.recent(), isEmpty);
      },
    );

    test('a just-sent fix stays: the window is three days', () async {
      final h = TestHarness();
      final recent = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      await h.queue.add(
        QueuedFix(
          id: 'new',
          latitude: 16.84,
          longitude: 96.17,
          capturedAt: recent,
        ),
      );
      await h.queue.markTransferred(['new']);

      await h.tracking.syncNow();

      expect((await h.queue.recent()).single.id, 'new');
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
    }

    testWidgets('the tab shows the tracking state and each fix mark', (
      tester,
    ) async {
      final h = TestHarness();
      await _pumpTab(tester, h, const LocationTab());
      await h.tracking.onSignedInChanged(true);
      await settle(tester);

      expect(find.text(S.locationOn), findsOneWidget);
      expect(
        find.textContaining('All fixes have been sent to the office.'),
        findsOneWidget,
      );

      h.location.emit(fix);
      await settle(tester);

      expect(find.text(S.sent), findsOneWidget);
      expect(find.textContaining('16.84090'), findsOneWidget);

      // Stop tracking so the periodic sync timer does not outlive the test.
      await h.tracking.onSignedInChanged(false);
      await settle(tester);
    });

    testWidgets('a blocked permission offers a way into settings', (
      tester,
    ) async {
      final location = FakeLocationService(
        access: LocationAccess.deniedForever,
      );
      final h = TestHarness(location: location);
      await _pumpTab(tester, h, const LocationTab());
      await h.tracking.onSignedInChanged(true);
      await settle(tester);

      expect(find.text(S.trackBlocked), findsOneWidget);

      await tester.tap(find.text(S.openSettings));
      await tester.pump();
      expect(location.settingsOpened, 1);
    });

    testWidgets(
      'battery optimisation that may stop tracking is offered a fix',
      (tester) async {
        final location = FakeLocationService(batteryIgnored: false);
        final h = TestHarness(location: location);
        await _pumpTab(tester, h, const LocationTab());
        await h.tracking.onSignedInChanged(true);
        await settle(tester);

        expect(find.text(S.batteryWarning), findsOneWidget);

        await tester.tap(find.text(S.allowBackground));
        await tester.pump();
        expect(location.batteryRequests, 1);

        await h.tracking.onSignedInChanged(false);
        await settle(tester);
      },
    );

    testWidgets('no battery nag when Android leaves the app alone', (
      tester,
    ) async {
      final h = TestHarness();
      await _pumpTab(tester, h, const LocationTab());
      await h.tracking.onSignedInChanged(true);
      await settle(tester);

      expect(find.text(S.allowBackground), findsNothing);

      await h.tracking.onSignedInChanged(false);
      await settle(tester);
    });
  });

  group('Delivery board screen', () {
    testWidgets('renders the man\'s own positions and totals', (tester) async {
      final h = TestHarness();
      h.api.deliveryBoardValue = _board();

      await tester.pumpWidget(
        AppScope(
          services: h.services,
          child: const MaterialApp(home: DeliveryBoardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(S.boardTitle), findsOneWidget);
      // Summary and the single filled position of group 1.
      expect(find.textContaining('1 / 2000'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text(S.groupHeading(1)), findsOneWidget);

      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      expect(find.textContaining('B1'), findsOneWidget);
    });
  });

  group('QR identity cache', () {
    testWidgets('the QR screen warns when it is showing a saved code', (
      tester,
    ) async {
      final h = TestHarness();
      h.api.qrValue = const QrIdentityDto(payload: 'lc1:opaque', issuedAt: 0);
      await h.repository.qr(); // cache it
      h.api.failure = const OfflineFailure();

      await tester.pumpWidget(
        AppScope(
          services: h.services,
          child: const MaterialApp(home: QrScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('last saved code'), findsOneWidget);
    });
  });

  group('No financial write surface', () {
    test(
      'every call the client can make is a read or an identity action',
      () async {
        // flutter_test mocks HttpClient by default; restore the real one so
        // this test can reach a loopback server.
        HttpOverrides.global = null;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final recorded = <String>[];
        server.listen((request) async {
          await utf8.decoder.bind(request).join();
          recorded.add('${request.method} ${request.uri.path}');
          final body = switch (request.uri.path) {
            ApiRoutes.login => {
              'token': 't',
              'expiresAt': 1,
              'profile': {'id': 'm1', 'name': 'A', 'phone': ''},
            },
            ApiRoutes.me => {'id': 'm1', 'name': 'A', 'phone': ''},
            ApiRoutes.summary => _summary.toJson(),
            ApiRoutes.commissions => {'items': <Object>[]},
            ApiRoutes.rewards => {'items': <Object>[]},
            ApiRoutes.deliveryBoard => const DeliveryBoardDto(
              summary: BoardSummaryDto(
                successfulDeliveries: 0,
                totalSlots: 2000,
                commissionEarned: 0,
                commissionPaid: 0,
                unpaidCommission: 0,
                rewardsEarned: 0,
                rewardsPaid: 0,
                unpaidBalance: 0,
              ),
              groups: [],
              slotsPerGroup: 10,
              totalSlots: 2000,
            ).toJson(),
            ApiRoutes.qr => {'payload': 'lc1:x', 'issuedAt': 1},
            ApiRoutes.locations =>
              request.method == 'POST'
                  ? const GeoPointDto(
                      id: 'g1',
                      latitude: 1,
                      longitude: 2,
                      capturedAt: 1,
                    ).toJson()
                  : {'items': <Object>[]},
            ApiRoutes.logout => {'ok': true},
            _ => const CommissionDto(
              id: 'r1',
              barcode: 'B1',
              commission: 1,
              dateTime: 1,
              paymentStatus: 'unpaid',
              reconciliationStatus: 'unknown',
            ).toJson(),
          };
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        });

        final api = HttpCompanionApi(
          baseUrlProvider: () => 'http://127.0.0.1:${server.port}',
        );
        await api.login(loginId: 'a', pin: '1234');
        await api.me();
        await api.summary();
        await api.commissions();
        await api.commission('r1');
        await api.rewards();
        await api.deliveryBoard();
        await api.qr();
        await api.locations();
        await api.recordLocation(latitude: 1, longitude: 2);
        await api.logout();
        await server.close(force: true);

        const allowedPosts = {
          ApiRoutes.login,
          ApiRoutes.logout,
          ApiRoutes.qr,
          ApiRoutes.qrRotate,
          ApiRoutes.locations,
        };
        for (final entry in recorded) {
          final method = entry.split(' ')[0];
          final path = entry.split(' ')[1];
          expect(method, anyOf('GET', 'POST'), reason: entry);
          if (method == 'POST') {
            expect(allowedPosts, contains(path), reason: entry);
          }
          if (path.contains('commission') || path.contains('reward')) {
            expect(method, 'GET', reason: '$entry must be read-only');
          }
        }
      },
    );
  });
}
