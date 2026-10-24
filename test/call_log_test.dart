import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/phone_number.dart';
import 'package:lab_commission/ui/call_log_screen.dart';

void main() {
  group('phone matching', () {
    test('the same Myanmar number in every written form matches', () {
      expect(normalizePhone('+95 9 77 1234 567'), '9771234567');
      expect(normalizePhone('0977 123 4567'), '9771234567');
      expect(samePhone('09771234567', '+959771234567'), isTrue);
      expect(samePhone('09771234567', '959771234567'), isTrue);
      // A local mobile must never be confused with the 95 country code.
      expect(normalizePhone('0950123456'), '950123456');
    });

    test('different or empty numbers never match', () {
      expect(samePhone('09771234567', '09881112222'), isFalse);
      expect(samePhone('', ''), isFalse);
      expect(samePhone('private', '09771234567'), isFalse);
      expect(samePhone('', '09771234567'), isFalse);
    });
  });

  group('call log service', () {
    late AppServices services;
    late String ayeId;
    late String moeId;

    setUp(() async {
      services = await AppServices.bootstrap(MemoryStorage());
      ayeId = (await services.deliveryMen.create(
        name: 'Aye Chan',
        phone: '09771234567',
      )).id;
      moeId = (await services.deliveryMen.create(
        name: 'Moe Thin',
        phone: '09881112222',
      )).id;
    });

    test(
      'a ring from a delivery man is logged with time and answer state',
      () async {
        final saved = await services.callLog.recordIncoming(
          number: '+959771234567',
          at: 1760000000000,
          answered: true,
        );
        expect(saved, isNotNull);
        expect(saved!.deliveryManId, ayeId);
        expect(saved.receivedAt, 1760000000000);
        expect(saved.answered, isTrue);
        // The number is kept exactly as the phone reported it.
        expect(saved.phone, '+959771234567');

        final listed = await services.callLog.recent();
        expect(listed.single.id, saved.id);
      },
    );

    test('a ring from anyone else is not logged', () async {
      final saved = await services.callLog.recordIncoming(
        number: '09123456789',
        at: 1,
        answered: false,
      );
      expect(saved, isNull);
      expect(await services.callLog.recent(), isEmpty);
    });

    test('a missed ring is logged the same way, marked not answered', () async {
      final saved = await services.callLog.recordIncoming(
        number: '09771234567',
        at: 100,
        answered: false,
      );
      expect(saved!.answered, isFalse);
    });

    test('latestByMan keeps only the newest call per man', () async {
      await services.callLog.recordIncoming(
        number: '09771234567',
        at: 100,
        answered: false,
      );
      await services.callLog.recordIncoming(
        number: '09771234567',
        at: 200,
        answered: true,
      );
      await services.callLog.recordIncoming(
        number: '09881112222',
        at: 150,
        answered: true,
      );

      final latest = await services.callLog.latestByMan();
      expect(latest, hasLength(2));
      expect(latest[ayeId]!.receivedAt, 200);
      expect(latest[ayeId]!.answered, isTrue);
      expect(latest[moeId]!.receivedAt, 150);
    });

    test('recent(forMan) narrows to one man, newest first', () async {
      await services.callLog.recordIncoming(
        number: '09771234567',
        at: 100,
        answered: true,
      );
      await services.callLog.recordIncoming(
        number: '09771234567',
        at: 300,
        answered: false,
      );
      await services.callLog.recordIncoming(
        number: '09881112222',
        at: 200,
        answered: true,
      );

      final aye = await services.callLog.recent(forMan: ayeId);
      expect(aye.map((c) => c.receivedAt), [300, 100]);
      expect(await services.callLog.recent(forMan: moeId), hasLength(1));
    });
  });

  testWidgets('the call log screen shows man, date/time and answered/missed', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.deliveryMen.create(name: 'Aye Chan', phone: '09771234567');
    await services.deliveryMen.create(name: 'Moe Thin', phone: '09881112222');
    await services.callLog.recordIncoming(
      number: '0977123 4567',
      at: DateTime(2026, 10, 20, 14, 32).millisecondsSinceEpoch,
      answered: false,
    );
    await services.callLog.recordIncoming(
      number: '09881112222',
      at: DateTime(2026, 10, 19, 9, 5).millisecondsSinceEpoch,
      answered: true,
    );

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CallLogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Call Log'), findsOneWidget);
    expect(find.text('Aye Chan'), findsOneWidget);
    expect(find.text('Moe Thin'), findsOneWidget);
    expect(find.textContaining('20/10/2026 14:32'), findsOneWidget);
    expect(find.textContaining('19/10/2026 09:05'), findsOneWidget);
    expect(find.textContaining('0977123 4567'), findsOneWidget);
    expect(find.text('missed'), findsOneWidget);
    expect(find.text('answered'), findsOneWidget);
  });

  testWidgets(
    'the call log screen filters to one man when opened from his card',
    (tester) async {
      final services = await AppServices.bootstrap(MemoryStorage());
      final aye = await services.deliveryMen.create(
        name: 'Aye Chan',
        phone: '09771234567',
      );
      await services.deliveryMen.create(name: 'Moe Thin', phone: '09881112222');
      await services.callLog.recordIncoming(
        number: '09771234567',
        at: 100,
        answered: true,
      );
      await services.callLog.recordIncoming(
        number: '09881112222',
        at: 200,
        answered: true,
      );

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(home: CallLogScreen(deliveryManId: aye.id)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Call Log · Aye Chan'), findsOneWidget);
      expect(find.text('Aye Chan'), findsOneWidget);
      expect(find.text('Moe Thin'), findsNothing);
    },
  );

  testWidgets('a call shows the receipts recorded for that man after it', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final man = await services.deliveryMen.create(
      name: 'Aye Chan',
      phone: '09771234567',
    );
    final staffId = (await services.users.all()).first.id;
    final calledAt = DateTime(2026, 10, 20, 9).millisecondsSinceEpoch;
    await services.callLog.recordIncoming(
      number: '09771234567',
      at: calledAt,
      answered: true,
    );
    for (final (barcode, minutes) in [('A1', 20), ('A2', 45)]) {
      await services.commissions.insert(
        CommissionRecord(
          id: barcode,
          barcode: barcode,
          deliveryManId: man.id,
          commission: 1000,
          dateTime: calledAt + minutes * 60 * 1000,
          staffUserId: staffId,
          createdAt: calledAt,
        ),
      );
    }

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CallLogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 receipts after this call'), findsOneWidget);
    await tester.tap(find.text('Aye Chan'));
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
  });
}
