import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/cash_screens.dart';

void main() {
  test('correcting an advance updates its ledger entry and audit trail', () async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1234');
    final userId = services.auth.requireUser().id;
    final advance = await services.cashService.addAdvance(
      amount: 100000,
      note: 'Owner advance',
      date: '2026-10-01',
      createdBy: userId,
    );

    await services.cashService.updateAdvance(
      id: advance.id,
      amount: 80000,
      date: '2026-10-03',
      note: 'Corrected owner advance',
      updatedBy: userId,
    );

    final updated = await services.cash.findAdvance(advance.id);
    expect(updated?.amount, 80000);
    expect(updated?.date, '2026-10-03');
    expect(updated?.note, 'Corrected owner advance');
    expect(await services.cash.balance(), 80000);

    final txns = await services.cash.ledger();
    expect(txns, hasLength(1));
    expect(txns.single.amount, 80000);
    expect(txns.single.date, '2026-10-03');
    expect(txns.single.note, 'Corrected owner advance');

    final logs = await services.audit.logs();
    expect(
      logs.where((l) => l.action == 'CASH_ADVANCE_EDITED'),
      hasLength(1),
    );
  });

  testWidgets('correcting a cash advance requires the admin PIN', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    // A staff login can open the screen (when allowed), but the correction
    // itself still needs the admin PIN.
    await services.auth.login('1111');
    final staffId = services.auth.requireUser().id;
    final advance = await services.cashService.addAdvance(
      amount: 100000,
      note: 'Owner advance',
      date: '2026-10-01',
      createdBy: staffId,
    );

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CashAdvanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Owner advance'), findsOneWidget);
    expect(find.text('+100,000 MMK'), findsOneWidget);

    Future<void> startCorrection() async {
      await tester.tap(find.byTooltip('Correct advance'));
      await tester.pumpAndSettle();
      expect(find.text('Correct cash advance'), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        '80000',
      );
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .last,
        'Corrected advance',
      );
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
    }

    await startCorrection();
    expect(find.text('Admin PIN'), findsOneWidget);

    // Cancelling the PIN check leaves the advance untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await services.cash.findAdvance(advance.id))?.amount, 100000);
    expect(await services.cash.balance(), 100000);

    await startCorrection();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '1234',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    final updated = await services.cash.findAdvance(advance.id);
    expect(updated?.amount, 80000);
    expect(updated?.note, 'Corrected advance');
    expect(await services.cash.balance(), 80000);
    expect(find.text('+80,000 MMK'), findsOneWidget);
    expect(find.text('Corrected advance'), findsOneWidget);
  });

  test(
    'deleting an advance reverses its cash effect and keeps an audit trail',
    () async {
      final services = await AppServices.bootstrap(MemoryStorage());
      await services.auth.login('1234');
      final userId = services.auth.requireUser().id;
      final advance = await services.cashService.addAdvance(
        amount: 100000,
        note: 'Owner advance',
        date: '2026-10-01',
        createdBy: userId,
      );

      await services.cashService.deleteAdvance(
        id: advance.id,
        byUserId: userId,
      );

      expect(await services.cash.findAdvance(advance.id), isNull);
      expect(await services.cash.advances(), isEmpty);
      expect(await services.cash.balance(), 0);

      // The original movement stays in the ledger, offset by a reversal entry.
      final txns = await services.cash.ledger();
      expect(txns, hasLength(2));
      expect(txns.map((t) => t.amount).toList()..sort(), [-100000, 100000]);
      expect(
        txns.where((t) => t.note.contains('Cash advance deleted')),
        hasLength(1),
      );

      final logs = await services.audit.logs();
      expect(
        logs.where((l) => l.action == 'CASH_ADVANCE_DELETED'),
        hasLength(1),
      );
    },
  );

  testWidgets('deleting a cash advance needs confirmation and the admin PIN', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1111');
    final staffId = services.auth.requireUser().id;
    final advance = await services.cashService.addAdvance(
      amount: 100000,
      note: 'Owner advance',
      date: '2026-10-01',
      createdBy: staffId,
    );

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CashAdvanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Owner advance'), findsOneWidget);

    // Cancelling the confirmation leaves the advance untouched.
    await tester.tap(find.byTooltip('Delete advance'));
    await tester.pumpAndSettle();
    expect(find.text('Delete cash advance?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.cash.findAdvance(advance.id), isNotNull);

    Future<void> startDelete() async {
      await tester.tap(find.byTooltip('Delete advance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();
      expect(find.text('Admin PIN'), findsOneWidget);
    }

    // Confirming without the admin PIN still keeps the advance.
    await startDelete();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.cash.findAdvance(advance.id), isNotNull);
    expect(await services.cash.balance(), 100000);

    // The correct PIN deletes it and refreshes the list.
    await startDelete();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '1234',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(await services.cash.findAdvance(advance.id), isNull);
    expect(await services.cash.balance(), 0);
    expect(find.text('Owner advance'), findsNothing);
    expect(find.text('No cash advances recorded yet.'), findsOneWidget);
  });
}
