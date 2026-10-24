import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:lab_delivery_companion/core/failure.dart';
import 'package:lab_delivery_companion/data/services/delivery_watch.dart';
import 'package:lab_delivery_companion/data/storage/seen_store.dart';

import 'support/fakes.dart';

/// A board whose group 1 holds the given successful positions.
DeliveryBoardDto _board(
  Map<int, int> commissionByPosition, {
  Set<int> paid = const {},
}) => DeliveryBoardDto(
  summary: const BoardSummaryDto(
    successfulDeliveries: 0,
    totalSlots: 2000,
    commissionEarned: 0,
    commissionPaid: 0,
    unpaidCommission: 0,
    rewardsEarned: 0,
    rewardsPaid: 0,
    unpaidBalance: 0,
  ),
  groups: [
    BoardGroupDto(
      groupNumber: 1,
      startNumber: 1,
      endNumber: 10,
      successfulCount: commissionByPosition.length,
      commissionTotal: commissionByPosition.values.fold(0, (a, b) => a + b),
      milestoneAmounts: const [],
      slots: [
        for (var n = 1; n <= 10; n++)
          if (commissionByPosition.containsKey(n))
            BoardSlotDto(
              number: n,
              state: 'successful',
              commission: commissionByPosition[n]!,
              paid: paid.contains(n),
              barcode: 'B$n',
              recordedAt: 1700000000000,
            )
          else
            BoardSlotDto(number: n, state: 'empty'),
      ],
    ),
  ],
  slotsPerGroup: 10,
  totalSlots: 2000,
);

void main() {
  group('New-delivery watch', () {
    late TestHarness h;
    late DeliveryWatch watch;

    setUp(() {
      h = TestHarness();
      watch = h.watch;
    });

    test('the first read only records the baseline', () async {
      h.api.deliveryBoardValue = _board({1: 10});

      await watch.check();

      expect(h.api.calls, contains('deliveryBoard'));
      expect(
        watch.pending,
        isEmpty,
        reason: 'a fresh install must not announce every past delivery',
      );
    });

    test('a delivery recorded after the baseline is announced once', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();

      h.api.deliveryBoardValue = _board({1: 10, 2: 25});
      await watch.check();

      expect(watch.pending, hasLength(1));
      expect(watch.pending.single.number, 2);
      expect(watch.pending.single.commission, 25);

      // A second identical read must not announce it again.
      await watch.check();
      expect(watch.pending, hasLength(1));
    });

    test('a board fetched elsewhere (pull-to-refresh) is announced too', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();

      // The board screen fetched a fresh board on pull-to-refresh; handing that
      // same result to the watch must announce the new delivery without a
      // second request.
      await watch.observe(_board({1: 10, 2: 25}));

      expect(watch.pending, hasLength(1));
      expect(watch.pending.single.number, 2);

      // Polling afterwards must not announce it a second time.
      h.api.deliveryBoardValue = _board({1: 10, 2: 25});
      await watch.check();
      expect(watch.pending, hasLength(1));
    });

    test('dismissing clears the alert but not the memory', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();
      h.api.deliveryBoardValue = _board({1: 10, 2: 25});
      await watch.check();

      watch.clear();
      expect(watch.pending, isEmpty);

      await watch.check();
      expect(watch.pending, isEmpty, reason: 'already seen, not new again');
    });

    test('an offline read announces nothing and keeps the queue', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();
      h.api.deliveryBoardValue = _board({1: 10, 2: 25});
      h.api.failure = const OfflineFailure();

      await watch.check();

      expect(watch.pending, isEmpty);
    });

    test('the amount, time and paid flag are reported', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();
      h.api.deliveryBoardValue = _board({1: 10, 2: 25}, paid: {2});
      await watch.check();

      final d = watch.pending.single;
      expect(d.amountLabel, contains('25 MMK'));
      expect(d.whenLabel, isNot('—'));
      expect(d.statusLabel, isNotEmpty);
    });

    test('reset forgets the baseline, so the next man starts clean', () async {
      h.api.deliveryBoardValue = _board({1: 10});
      await watch.check();

      await watch.reset();
      h.api.deliveryBoardValue = _board({1: 10, 2: 25});
      await watch.check();

      expect(watch.pending, isEmpty);
    });
  });

  group('Seen store', () {
    test('a corrupt stored value is ignored, not fatal', () async {
      final store = MemorySeenStore();
      await store.write('deliveryWatch', 'not json');
      final watch = DeliveryWatch(
        repository: TestHarness().repository,
        store: store,
      );

      watch.check(); // must not throw
      expect(watch.pending, isEmpty);
    });
  });
}
