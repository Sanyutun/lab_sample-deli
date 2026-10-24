import '../data/models/models.dart';

/// Visual states for a single delivery slot on the board.
enum DeliverySlotState {
  /// No real delivery occupies this position.
  empty,

  /// Active delivery, verified by reconciliation (or no reconciliation run yet).
  successful,

  /// Active delivery whose official receipt has not been verified yet.
  pending,

  /// Reversed delivery. Kept for audit; the original transaction is preserved.
  reversed,
}

/// One numbered position on the delivery board.
///
/// Slots are a *visual* representation of delivery positions. They do not
/// create or imply a financial transaction; only real records are attached.
class DeliverySlot {
  const DeliverySlot({
    required this.number,
    required this.state,
    this.record,
    this.milestoneAmount,
    this.reconciliationStatus,
  });

  /// Stable sequential display number (1-based) for the delivery man.
  final int number;

  final DeliverySlotState state;

  /// The underlying authoritative transaction, when a real delivery exists.
  final CommissionRecord? record;

  /// Amount of the milestone reward earned exactly at this position, if any.
  final int? milestoneAmount;

  /// Latest reconciliation status for this barcode, when available.
  final ReconciliationStatus? reconciliationStatus;

  bool get isEmpty => state == DeliverySlotState.empty;
  bool get hasRecord => record != null;
  int get commission => record?.commission ?? 0;
}

/// A group of [slotsPerGroup] delivery slots (default 10, laid out 5 x 2).
class DeliveryGroup {
  const DeliveryGroup({
    required this.groupNumber,
    required this.startNumber,
    required this.endNumber,
    required this.slots,
    required this.successfulCount,
    required this.commissionTotal,
    required this.milestoneAmounts,
  });

  /// 1-based group number.
  final int groupNumber;
  final int startNumber;
  final int endNumber;
  final List<DeliverySlot> slots;

  /// Successful deliveries physically located in this group.
  final int successfulCount;

  /// Commission earned by the successful deliveries of this group.
  final int commissionTotal;

  /// Amounts of the milestone rewards earned at positions inside this group,
  /// in position order. Empty when the group earned none.
  final List<int> milestoneAmounts;
}

/// Aggregated per-delivery-man totals, always derived from authoritative records.
class DeliveryBoardSummary {
  const DeliveryBoardSummary({
    required this.successfulDeliveries,
    required this.totalSlots,
    required this.commissionEarned,
    required this.commissionPaid,
    required this.unpaidCommission,
    required this.rewardsEarned,
    required this.rewardsPaid,
    required this.unpaidBalance,
  });

  final int successfulDeliveries;
  final int totalSlots;
  final int commissionEarned;
  final int commissionPaid;
  final int unpaidCommission;
  final int rewardsEarned;
  final int rewardsPaid;
  final int unpaidBalance;
}

/// Immutable view model for the whole board.
class DeliveryBoard {
  const DeliveryBoard({
    required this.groups,
    required this.summary,
    required this.slotsPerGroup,
    required this.totalSlots,
  });

  final List<DeliveryGroup> groups;
  final DeliveryBoardSummary summary;
  final int slotsPerGroup;
  final int totalSlots;

  static const int defaultSlotsPerGroup = 10;
  static const int defaultGroupCount = 200;

  /// Builds the board from authoritative repositories' data.
  ///
  /// [records] must contain every commission record for the delivery man,
  /// including reversed ones, so display numbers stay stable after a reversal.
  /// This function never writes anything and never creates rewards.
  factory DeliveryBoard.from({
    required List<CommissionRecord> records,
    required List<MilestoneReward> rewards,
    Map<String, ReconciliationStatus> reconciliationByBarcode = const {},
    int slotsPerGroup = defaultSlotsPerGroup,
    int groupCount = defaultGroupCount,
  }) {
    final totalSlots = slotsPerGroup * groupCount;

    // Stable display numbering: ascending by transaction time, ties broken by id.
    final ordered = [...records]
      ..sort((a, b) {
        final byTime = a.dateTime.compareTo(b.dateTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    final byNumber = <int, CommissionRecord>{};
    for (var i = 0; i < ordered.length && i < totalSlots; i++) {
      byNumber[i + 1] = ordered[i];
    }

    // Milestone positions, taken from rewards actually recorded by the service.
    // The every-N count of a rule is admin-editable, so a mark follows the
    // reward's own count rather than a fixed 10 or 150.
    final milestoneByPosition = <int, int>{};
    for (final reward in rewards) {
      if (reward.status != RecordStatus.active) continue;
      final kept = milestoneByPosition[reward.milestoneCount];
      if (kept == null || reward.rewardAmount > kept) {
        milestoneByPosition[reward.milestoneCount] = reward.rewardAmount;
      }
    }

    final groups = <DeliveryGroup>[];
    for (var g = 1; g <= groupCount; g++) {
      final start = (g - 1) * slotsPerGroup + 1;
      final end = g * slotsPerGroup;
      final slots = <DeliverySlot>[];
      var successful = 0;
      var commission = 0;

      for (var n = start; n <= end; n++) {
        final record = byNumber[n];
        final reconStatus = record == null
            ? null
            : reconciliationByBarcode[record.barcode];
        final state = _stateFor(record, reconStatus);
        if (state == DeliverySlotState.successful ||
            state == DeliverySlotState.pending) {
          successful++;
          commission += record!.commission;
        }
        slots.add(
          DeliverySlot(
            number: n,
            state: state,
            record: record,
            milestoneAmount: milestoneByPosition[n],
            reconciliationStatus: reconStatus,
          ),
        );
      }

      groups.add(
        DeliveryGroup(
          groupNumber: g,
          startNumber: start,
          endNumber: end,
          slots: slots,
          successfulCount: successful,
          commissionTotal: commission,
          milestoneAmounts: [
            for (var n = start; n <= end; n++)
              if (milestoneByPosition[n] != null) milestoneByPosition[n]!,
          ],
        ),
      );
    }

    var successfulDeliveries = 0;
    var commissionEarned = 0;
    var commissionPaid = 0;
    for (final r in records) {
      if (r.status != RecordStatus.active) continue;
      successfulDeliveries++;
      commissionEarned += r.commission;
      if (r.paymentStatus == PaymentStatus.paid) commissionPaid += r.commission;
    }

    var rewardsEarned = 0;
    var rewardsPaid = 0;
    for (final r in rewards) {
      if (r.status != RecordStatus.active) continue;
      rewardsEarned += r.rewardAmount;
      if (r.paymentStatus == PaymentStatus.paid) rewardsPaid += r.rewardAmount;
    }

    final summary = DeliveryBoardSummary(
      successfulDeliveries: successfulDeliveries,
      totalSlots: totalSlots,
      commissionEarned: commissionEarned,
      commissionPaid: commissionPaid,
      unpaidCommission: commissionEarned - commissionPaid,
      rewardsEarned: rewardsEarned,
      rewardsPaid: rewardsPaid,
      unpaidBalance:
          (commissionEarned - commissionPaid) + (rewardsEarned - rewardsPaid),
    );

    return DeliveryBoard(
      groups: groups,
      summary: summary,
      slotsPerGroup: slotsPerGroup,
      totalSlots: totalSlots,
    );
  }

  static DeliverySlotState _stateFor(
    CommissionRecord? record,
    ReconciliationStatus? reconStatus,
  ) {
    if (record == null) return DeliverySlotState.empty;
    if (record.status == RecordStatus.reversed) {
      return DeliverySlotState.reversed;
    }
    if (reconStatus == ReconciliationStatus.notFound ||
        reconStatus == ReconciliationStatus.mismatch) {
      return DeliverySlotState.pending;
    }
    return DeliverySlotState.successful;
  }
}
