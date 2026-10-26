import '../../domain/exceptions.dart';
import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

/// Commission rules + commission records (transactions).
class CommissionRepository {
  CommissionRepository(this._storage);
  final AppStorage _storage;

  static const String rulesTable = 'commission_rules';
  static const String recordsTable = 'commission_records';

  // ---- rules ----

  Future<void> seedRules() async {
    if ((await rules()).isEmpty) {
      // Shop rule: under 10,000 -> 1,000; 10,000 to 100,000 -> 2,000;
      // over 100,000 -> 3,000. Bounds are inclusive, so the bands meet with no
      // gap and no overlap. Admin can change any of this (see admin settings).
      await addRule(minAmount: 0, maxAmount: 9999, commissionAmount: 1000);
      await addRule(
        minAmount: 10000,
        maxAmount: 100000,
        commissionAmount: 2000,
      );
      await addRule(minAmount: 100001, maxAmount: null, commissionAmount: 3000);
      return;
    }
    await _migrateOldDefaultBands();
  }

  /// The bands an earlier build seeded, replaced once by the shop rule above.
  ///
  /// Only the exact old triple is touched, so a shop that has already set its
  /// own bands keeps them; the rule count must also match so a customised set
  /// that happens to share a boundary is never rewritten.
  static const List<(int, int?, int)> _oldDefaultBands = [
    (0, 49999, 1000),
    (50000, 99999, 2000),
    (100000, null, 3000),
  ];

  Future<void> _migrateOldDefaultBands() async {
    final existing = await rules();
    if (existing.length != _oldDefaultBands.length) return;
    for (var i = 0; i < existing.length; i++) {
      final (min, max, amount) = _oldDefaultBands[i];
      final r = existing[i];
      if (r.minAmount != min ||
          r.maxAmount != max ||
          r.commissionAmount != amount) {
        return;
      }
    }
    for (final r in existing) {
      await _storage.remove(rulesTable, {'id': r.id});
    }
    await addRule(minAmount: 0, maxAmount: 9999, commissionAmount: 1000);
    await addRule(minAmount: 10000, maxAmount: 100000, commissionAmount: 2000);
    await addRule(minAmount: 100001, maxAmount: null, commissionAmount: 3000);
  }

  Future<CommissionRule> addRule({
    required int minAmount,
    required int? maxAmount,
    required int commissionAmount,
    bool active = true,
  }) async {
    await _validateBand(
      minAmount: minAmount,
      maxAmount: maxAmount,
      commissionAmount: commissionAmount,
    );
    final rule = CommissionRule(
      id: newId('rule'),
      minAmount: minAmount,
      maxAmount: maxAmount,
      commissionAmount: commissionAmount,
      active: active,
    );
    await _storage.insert(rulesTable, rule.toMap());
    return rule;
  }

  Future<List<CommissionRule>> rules({bool activeOnly = false}) async {
    final rows = await _storage.find(rulesTable, orderBy: 'min_amount');
    final rules = rows.map(CommissionRule.fromMap).toList();
    return activeOnly ? rules.where((r) => r.active).toList() : rules;
  }

  Future<void> updateRule(CommissionRule rule) async {
    await _validateBand(
      minAmount: rule.minAmount,
      maxAmount: rule.maxAmount,
      commissionAmount: rule.commissionAmount,
      ignoreId: rule.id,
    );
    await _storage.update(rulesTable, {'id': rule.id}, rule.toMap());
  }

  /// Bands are inclusive and [expectedCommission] takes the first match, so an
  /// overlap would silently make one of the two bands useless. Rejected bands
  /// are checked too, otherwise switching one back on would create the overlap.
  Future<void> _validateBand({
    required int minAmount,
    required int? maxAmount,
    required int commissionAmount,
    String? ignoreId,
  }) async {
    if (minAmount < 0) {
      throw const ValidationException(
        'Minimum receipt total cannot be negative',
      );
    }
    if (maxAmount != null && maxAmount < minAmount) {
      throw const ValidationException(
        'Maximum receipt total must be the same as or larger than the minimum',
      );
    }
    if (commissionAmount < 1) {
      throw const ValidationException(
        'Commission amount must be 1 MMK or more',
      );
    }
    for (final other in await rules()) {
      if (other.id == ignoreId) continue;
      final overlaps =
          (maxAmount == null || other.minAmount <= maxAmount) &&
          (other.maxAmount == null || minAmount <= other.maxAmount!);
      if (overlaps) {
        throw ValidationException(
          'This band overlaps the existing band '
          '${other.minAmount}-${other.maxAmount ?? 'no limit'}',
        );
      }
    }
  }

  /// Expected commission for an official receipt total, from configured rules.
  Future<int?> expectedCommission(int receiptTotal) async {
    final active = await rules(activeOnly: true);
    for (final r in active) {
      if (r.matches(receiptTotal)) return r.commissionAmount;
    }
    return null;
  }

  /// Amounts staff can select (derived from active rules, default 1000/2000/3000).
  Future<List<int>> selectableAmounts() async {
    final active = await rules(activeOnly: true);
    final amounts = active.map((r) => r.commissionAmount).toSet().toList()
      ..sort();
    return amounts;
  }

  // ---- records ----

  Future<CommissionRecord> findByBarcode(
    String barcode, {
    bool activeOnly = true,
  }) async {
    final rows = await _storage.find(recordsTable, where: {'barcode': barcode});
    final records = rows.map(CommissionRecord.fromMap).toList();
    if (activeOnly) {
      final active = records.where((r) => r.isActive).toList();
      if (active.isNotEmpty) return active.first;
      if (records.isNotEmpty) return records.first;
      throw const NotFoundException('Receipt not found');
    }
    if (records.isEmpty) throw const NotFoundException('Receipt not found');
    return records.first;
  }

  Future<bool> hasActiveByBarcode(String barcode) async {
    final rows = await _storage.find(recordsTable, where: {'barcode': barcode});
    return rows.any((r) => r['status'] == RecordStatus.active.name);
  }

  Future<CommissionRecord?> findById(String id) async {
    final m = await _storage.findOne(recordsTable, {'id': id});
    return m == null ? null : CommissionRecord.fromMap(m);
  }

  Future<CommissionRecord> insert(CommissionRecord record) async {
    if (await hasActiveByBarcode(record.barcode)) {
      final existing = await findByBarcode(record.barcode);
      throw DuplicateBarcodeException(existing);
    }
    try {
      await _storage.insert(recordsTable, record.toMap());
    } on Exception {
      // unique index fallback
      if (await hasActiveByBarcode(record.barcode)) {
        final existing = await findByBarcode(record.barcode);
        throw DuplicateBarcodeException(existing);
      }
      rethrow;
    }
    return record;
  }

  Future<void> updateRecord(CommissionRecord record) async {
    await _storage.update(recordsTable, {'id': record.id}, record.toMap());
  }

  Future<List<CommissionRecord>> all({
    String? deliveryManId,
    RecordStatus? status,
    String? staffUserId,
    bool descending = true,
  }) async {
    final rows = await _storage.find(recordsTable);
    var list = rows.map(CommissionRecord.fromMap).toList();
    if (deliveryManId != null) {
      list = list.where((r) => r.deliveryManId == deliveryManId).toList();
    }
    if (status != null) list = list.where((r) => r.status == status).toList();
    if (staffUserId != null) {
      list = list.where((r) => r.staffUserId == staffUserId).toList();
    }
    list.sort(
      (a, b) => descending
          ? b.dateTime.compareTo(a.dateTime)
          : a.dateTime.compareTo(b.dateTime),
    );
    return list;
  }

  Future<int> activeCountFor(String deliveryManId) async => (await all(
    deliveryManId: deliveryManId,
    status: RecordStatus.active,
  )).length;
}
