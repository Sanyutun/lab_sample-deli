import 'package:intl/intl.dart';

import 'strings.dart';

/// Monetary values are always MMK integers, formatted once here.
String fmtMMK(int amount) => '${NumberFormat('#,###').format(amount)} MMK';

String fmtDateTime(int ms) =>
    DateFormat('dd/MM/yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));

String fmtDate(int ms) =>
    DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// ISO `yyyy-MM-dd`, the form the office API expects for date filters.
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String paymentLabel(bool paid) => paid ? S.badgePaid : S.badgeUnpaid;

/// Human wording for a tracking duration, e.g. "2 minutes", "1 minute" or
/// "3 days".
String fmtMinutes(Duration d) {
  if (d.inMinutes >= 1440 && d.inMinutes % 1440 == 0) {
    return S.nDays(d.inDays);
  }
  final m = d.inMinutes;
  return m == 1 ? S.oneMinute : S.nMinutes(m);
}

/// Office cash-ledger types, as they arrive in a commission's payment history.
String paymentEntryLabel(String type) => switch (type) {
  'advance' => S.entryAdvance,
  'commissionPayment' => S.entryCommission,
  'rewardPayment' => S.entryReward,
  'otherIn' => S.entryOtherIn,
  'otherOut' => S.entryOtherOut,
  _ => type,
};

/// Reward rule wording, built from the office's own reward record.
String rewardRuleLabel(int everyN, int rewardAmount) =>
    S.everyNDeliveries(everyN, fmtMMK(rewardAmount));

String reconciliationLabel(String status) => switch (status) {
  'match' => S.recMatch,
  'mismatch' => S.recMismatch,
  'notFound' => S.recNotFound,
  'duplicateStaff' || 'duplicateOfficial' => S.recDuplicate,
  'unclaimed' => S.recUnclaimed,
  _ => S.recNone,
};

/// Accuracy line for a GPS fix, honest about a missing reading.
String accuracyLabel(double? accuracyM) => accuracyM == null
    ? S.accuracyUnknown
    : S.accuracyMetres(accuracyM.toStringAsFixed(0));
