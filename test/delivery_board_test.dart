import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/delivery_board.dart';
import 'package:lab_commission/main.dart';
import 'package:lab_commission/ui/scan_flow.dart';

CommissionRecord _rec(
  String id,
  int dt, {
  int commission = 2000,
  String barcode = '',
  RecordStatus status = RecordStatus.active,
  PaymentStatus payment = PaymentStatus.unpaid,
}) => CommissionRecord(
  id: id,
  barcode: barcode.isEmpty ? 'BC_$id' : barcode,
  deliveryManId: 'dm1',
  commission: commission,
  dateTime: dt,
  staffUserId: 's1',
  status: status,
  paymentStatus: payment,
  createdAt: dt,
);

MilestoneReward _reward(
  int everyN,
  int count, {
  int amount = 4000,
  PaymentStatus payment = PaymentStatus.unpaid,
}) => MilestoneReward(
  id: 'rw-$everyN-$count',
  deliveryManId: 'dm1',
  everyN: everyN,
  milestoneCount: count,
  rewardAmount: amount,
  paymentStatus: payment,
  createdAt: count,
);

void main() {
  group('Delivery board layout', () {
    test('builds 200 groups x 10 slots = 2,000 positions, all empty', () {
      final board = DeliveryBoard.from(records: const [], rewards: const []);
      expect(board.groups, hasLength(200));
      expect(board.totalSlots, 2000);
      expect(board.groups.first.slots, hasLength(10));
      expect(board.groups.first.slots.first.state, DeliverySlotState.empty);
      expect(board.groups.last.slots.last.number, 2000);
      expect(board.summary.successfulDeliveries, 0);
      expect(board.summary.commissionEarned, 0);
      expect(board.summary.unpaidBalance, 0);
    });

    test('assigns stable sequential numbers and preserves them after reversal', () {
      final board = DeliveryBoard.from(
        records: [
          _rec('c', 300),
          _rec('a', 100),
          _rec('b', 200, status: RecordStatus.reversed),
        ],
        rewards: const [],
      );
      // ordered by dateTime: a(1), b(2), c(3) - reversed record keeps its slot
      expect(board.groups[0].slots[0].record!.id, 'a');
      expect(board.groups[0].slots[1].record!.id, 'b');
      expect(board.groups[0].slots[1].state, DeliverySlotState.reversed);
      expect(board.groups[0].slots[2].record!.id, 'c');
      expect(board.groups[0].slots[3].state, DeliverySlotState.empty);

      // later delivery is appended, existing numbers do not shift
      final later = DeliveryBoard.from(
        records: [
          _rec('c', 300),
          _rec('a', 100),
          _rec('b', 200, status: RecordStatus.reversed),
          _rec('d', 400),
        ],
        rewards: const [],
      );
      expect(later.groups[0].slots[0].number, 1);
      expect(later.groups[0].slots[1].number, 2);
      expect(later.groups[0].slots[2].number, 3);
      expect(later.groups[0].slots[3].record!.id, 'd');
      expect(later.groups[0].slots[3].number, 4);
    });

    test(
      'maps reconciliation results to successful vs pending verification',
      () {
        final board = DeliveryBoard.from(
          records: [
            _rec('a', 100, barcode: 'MATCHED'),
            _rec('b', 200, barcode: 'MISSING'),
            _rec('c', 300, barcode: 'MISMATCHED'),
          ],
          rewards: const [],
          reconciliationByBarcode: {
            'MATCHED': ReconciliationStatus.match,
            'MISSING': ReconciliationStatus.notFound,
            'MISMATCHED': ReconciliationStatus.mismatch,
          },
        );
        expect(board.groups[0].slots[0].state, DeliverySlotState.successful);
        expect(board.groups[0].slots[1].state, DeliverySlotState.pending);
        expect(board.groups[0].slots[2].state, DeliverySlotState.pending);
      },
    );

    test('marks milestone positions from the rewards that were earned', () {
      final board = DeliveryBoard.from(
        records: const [],
        rewards: [
          _reward(10, 10),
          _reward(10, 150),
          _reward(150, 150, amount: 150000),
        ],
      );
      expect(board.groups[0].milestoneAmounts, [4000]);
      expect(board.groups[0].slots[9].milestoneAmount, 4000);
      expect(board.groups[0].slots[0].milestoneAmount, isNull);
      // Position 150 earned two rewards; the position keeps the larger amount.
      expect(board.groups[14].milestoneAmounts, [150000]);
      expect(board.groups[14].slots[9].milestoneAmount, 150000);
    });

    test('an admin-edited rule marks its own position and amount', () {
      final board = DeliveryBoard.from(
        records: const [],
        rewards: [_reward(20, 20, amount: 8000)],
      );
      expect(board.groups[1].slots[9].milestoneAmount, 8000);
      expect(board.groups[1].milestoneAmounts, [8000]);
      expect(board.groups[0].milestoneAmounts, isEmpty);
    });

    test('summary keeps earned, paid and reward totals distinct', () {
      final board = DeliveryBoard.from(
        records: [
          _rec('a', 100, commission: 1000, payment: PaymentStatus.paid),
          _rec('b', 200, commission: 2000),
          _rec('c', 300, commission: 3000),
          _rec('d', 400, commission: 3000, status: RecordStatus.reversed),
        ],
        rewards: [
          _reward(10, 10),
          _reward(150, 150, amount: 150000, payment: PaymentStatus.paid),
        ],
      );
      final s = board.summary;
      expect(s.successfulDeliveries, 3);
      expect(s.commissionEarned, 6000);
      expect(s.commissionPaid, 1000);
      expect(s.unpaidCommission, 5000);
      expect(s.rewardsEarned, 154000);
      expect(s.rewardsPaid, 150000);
      expect(s.unpaidBalance, 5000 + 4000);
    });
  });

  group('Successful Delivery screen', () {
    testWidgets('renders the board and never creates transactions on open', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final services = await AppServices.bootstrap(MemoryStorage());
      await services.deliveryMen.create(name: 'Ko Aung');
      await tester.pumpWidget(LabCommissionApp(services: services));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1111');
      await tester.tap(find.text('LOGIN'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delivery Board'));
      await tester.pumpAndSettle();

      expect(find.text('Successful Delivery'), findsOneWidget);
      expect(find.text('Group 1'), findsOneWidget);
      // Opening the screen must not create records or rewards.
      expect(await services.commissions.all(), isEmpty);
      expect(await services.milestones.rewards(), isEmpty);

      // Tapping an empty slot must not create a delivery.
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Empty slot'), findsOneWidget);
      expect(await services.commissions.all(), isEmpty);
      expect(await services.milestones.rewards(), isEmpty);
    });

    testWidgets(
      'shows a successful delivery as a green card and opens the detail sheet',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final services = await AppServices.bootstrap(MemoryStorage());
        final man = await services.deliveryMen.create(name: 'Ko Aung');
        final users = await services.users.all();
        final staff = users.firstWhere((u) => !u.isAdmin);
        await services.delivery.recordCommission(
          barcode: '100125',
          deliveryManId: man.id,
          commission: 2000,
          staffUserId: staff.id,
        );

        await tester.pumpWidget(LabCommissionApp(services: services));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1111');
        await tester.tap(find.text('LOGIN'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delivery Board'));
        await tester.pumpAndSettle();

        expect(find.text('Group 1'), findsOneWidget);
        await tester.tap(find.text('01'));
        await tester.pumpAndSettle();

        expect(find.text('Receipt barcode'), findsOneWidget);
        expect(find.text('100125'), findsOneWidget);
        expect(find.textContaining('SUCCESSFUL'), findsOneWidget);
        // The detail sheet also carries this transaction's audit trail.
        expect(find.text('Audit trail'), findsOneWidget);
        expect(find.text('COMMISSION_RECORDED'), findsOneWidget);
        // still exactly one record / no duplicate reward created by opening
        expect(await services.commissions.all(), hasLength(1));
        expect(await services.milestones.rewards(), isEmpty);
      },
    );

    testWidgets('delivery recorded screen shows the same delivery card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final services = await AppServices.bootstrap(MemoryStorage());
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final users = await services.users.all();
      final staff = users.firstWhere((u) => !u.isAdmin);
      final result = await services.delivery.recordCommission(
        barcode: '100125',
        deliveryManId: man.id,
        commission: 2000,
        staffUserId: staff.id,
      );

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: DeliverySuccessScreen(
              record: result.record,
              rewards: result.rewards,
              deliveryManName: man.name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery Recorded'), findsOneWidget);
      expect(find.text('SUCCESSFUL DELIVERY'), findsOneWidget);
      expect(find.text('Group 1'), findsOneWidget);
      expect(find.textContaining('This delivery is card 1'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('UNPAID'), findsOneWidget);
      // all 10 cards of the group are shown
      expect(find.text('10'), findsOneWidget);

      // tapping the card marks it paid after a confirmation and persists
      await services.auth.login('1111');
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Pay now'));
      await tester.pumpAndSettle();
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('UNPAID'), findsNothing);
      final updated = await services.commissions.findById(result.record.id);
      expect(updated!.isPaid, isTrue);

      // tapping again takes the payment back, but only with the admin PIN
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      expect(find.text('Admin approval needed'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('UNPAID'), findsOneWidget);
      final reverted = await services.commissions.findById(result.record.id);
      expect(reverted!.isPaid, isFalse);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('board card can be marked paid, and only the admin PIN can '
        'take it back', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final services = await AppServices.bootstrap(MemoryStorage());
      final man = await services.deliveryMen.create(name: 'Ko Aung');
      final users = await services.users.all();
      final staff = users.firstWhere((u) => !u.isAdmin);
      final result = await services.delivery.recordCommission(
        barcode: '100125',
        deliveryManId: man.id,
        commission: 2000,
        staffUserId: staff.id,
      );

      await tester.pumpWidget(LabCommissionApp(services: services));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1111');
      await tester.tap(find.text('LOGIN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delivery Board'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();

      // Staff marks the delivery paid: confirmation, no PIN.
      expect(find.text('UNPAID'), findsWidgets);
      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Pay now'));
      await tester.pumpAndSettle();

      expect(find.text('Commission paid (-2,000 MMK)'), findsOneWidget);
      expect(
        (await services.commissions.findById(result.record.id))!.isPaid,
        isTrue,
      );
      expect(await services.cashService.balance(), -2000);

      // Reopen: now paid. Let the snackbar expire so it cannot block taps.
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('PAID'), findsWidgets);

      // A wrong admin PIN changes nothing.
      await tester.tap(find.text('Take payment back'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '9999',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(
        (await services.commissions.findById(result.record.id))!.isPaid,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // The admin PIN takes the payment back and the ledger returns it.
      await tester.tap(find.text('Take payment back'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Payment taken back (+2,000 MMK)'), findsOneWidget);
      expect(
        (await services.commissions.findById(result.record.id))!.isPaid,
        isFalse,
      );
      expect(await services.cashService.balance(), 0);

      await tester.pump(const Duration(seconds: 10));
    });
  });
}
