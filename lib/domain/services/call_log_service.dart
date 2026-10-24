import '../../data/models/models.dart';
import '../../data/repositories/call_log_repository.dart';
import '../../data/repositories/delivery_man_repository.dart';
import '../ids.dart';
import '../phone_number.dart';

/// Incoming-call evidence: matches rings against the registered delivery-man
/// phone numbers and keeps the log the office reads when a man claims he sent
/// a patient in. The lab gets calls from everywhere — only a registered
/// number becomes a log entry.
class CallLogService {
  CallLogService({required this.calls, required this.deliveryMen});

  final CallLogRepository calls;
  final DeliveryManRepository deliveryMen;

  /// Records one ring from [number] when it belongs to a delivery man.
  /// Returns the saved call, or null when the number matched nobody.
  Future<DeliveryManCall?> recordIncoming({
    required String number,
    required int at,
    required bool answered,
  }) async {
    final match = await _matchMan(number);
    if (match == null) return null;
    final call = DeliveryManCall(
      id: newId('call'),
      deliveryManId: match.id,
      phone: number,
      receivedAt: at,
      answered: answered,
    );
    await calls.insert(call);
    return call;
  }

  /// The call log, newest first; [forMan] narrows it to one delivery man.
  Future<List<DeliveryManCall>> recent({String? forMan}) =>
      calls.all(deliveryManId: forMan);

  /// The newest call per delivery man — what the picker and the man list
  /// show next to each phone number.
  Future<Map<String, DeliveryManCall>> latestByMan() async {
    // [calls.all] is newest first, so the first call seen per man wins.
    final latest = <String, DeliveryManCall>{};
    for (final c in await calls.all()) {
      latest.putIfAbsent(c.deliveryManId, () => c);
    }
    return latest;
  }

  Future<DeliveryMan?> _matchMan(String number) async {
    if (normalizePhone(number).isEmpty) return null;
    for (final man in await deliveryMen.all()) {
      if (samePhone(man.phone, number)) return man;
    }
    return null;
  }
}

/// Connects each recorded receipt to the call that announced it.
///
/// A man may call once and send one, two or more patients. A receipt is put
/// under the latest call from the same man on the same calendar day, so
/// receipts after his next call move to that next call and are not counted
/// twice. Receipts with no call before them that day stay unlinked.
Map<String, List<CommissionRecord>> receiptsByCall(
  List<DeliveryManCall> calls,
  List<CommissionRecord> records,
) {
  final callsByMan = <String, List<DeliveryManCall>>{};
  for (final call in calls) {
    callsByMan.putIfAbsent(call.deliveryManId, () => []).add(call);
  }
  for (final list in callsByMan.values) {
    list.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  }

  final linked = <String, List<CommissionRecord>>{};
  for (final record in records) {
    final manCalls = callsByMan[record.deliveryManId];
    if (manCalls == null) continue;
    DeliveryManCall? match;
    for (final call in manCalls) {
      if (call.receivedAt > record.dateTime) break;
      match = call;
    }
    if (match == null || !_sameDay(match.receivedAt, record.dateTime)) {
      continue;
    }
    linked.putIfAbsent(match.id, () => []).add(record);
  }
  for (final list in linked.values) {
    list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }
  return linked;
}

bool _sameDay(int a, int b) {
  final da = DateTime.fromMillisecondsSinceEpoch(a);
  final db = DateTime.fromMillisecondsSinceEpoch(b);
  return da.year == db.year && da.month == db.month && da.day == db.day;
}
