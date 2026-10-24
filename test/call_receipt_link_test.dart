import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/domain/services/call_log_service.dart';

DeliveryManCall _call(String id, String man, DateTime at) => DeliveryManCall(
  id: id,
  deliveryManId: man,
  phone: '09',
  receivedAt: at.millisecondsSinceEpoch,
  answered: true,
);

CommissionRecord _record(String id, String man, DateTime at) =>
    CommissionRecord(
      id: id,
      barcode: 'R$id',
      deliveryManId: man,
      commission: 1000,
      dateTime: at.millisecondsSinceEpoch,
      staffUserId: 'u1',
      createdAt: at.millisecondsSinceEpoch,
    );

void main() {
  test('receipts stay with the latest call from that man that day', () {
    final calls = [
      _call('a', 'm1', DateTime(2026, 10, 23, 9)),
      _call('b', 'm1', DateTime(2026, 10, 23, 15)),
      _call('c', 'm1', DateTime(2026, 10, 24, 11)),
    ];
    final records = [
      _record('before', 'm1', DateTime(2026, 10, 23, 8)),
      _record('r1', 'm1', DateTime(2026, 10, 23, 9, 30)),
      _record('r2', 'm1', DateTime(2026, 10, 23, 10)),
      _record('r3', 'm1', DateTime(2026, 10, 23, 16)),
      _record('other-man', 'm2', DateTime(2026, 10, 23, 10)),
      _record('next-morning', 'm1', DateTime(2026, 10, 24, 10)),
      _record('r4', 'm1', DateTime(2026, 10, 24, 12)),
    ];

    final linked = receiptsByCall(calls, records);

    expect(linked['a']!.map((r) => r.id), ['r1', 'r2']);
    expect(linked['b']!.map((r) => r.id), ['r3']);
    expect(linked['c']!.map((r) => r.id), ['r4']);
    final all = linked.values.expand((list) => list).map((r) => r.id);
    expect(all, isNot(contains('before')));
    expect(all, isNot(contains('next-morning')));
    expect(all, isNot(contains('other-man')));
  });
}
