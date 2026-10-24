import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/data/backup_schema.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/repositories/commission_repository.dart';
import 'package:lab_commission/domain/exceptions.dart';
import 'package:lab_commission/domain/ids.dart';
import 'package:lab_commission/domain/period.dart';
import 'package:lab_commission/domain/services/google_sheets_service.dart';
import 'package:lab_commission/domain/services/reconciliation_service.dart';
import 'package:lab_commission/ui/excel_export.dart';

class FakeSheetsClient implements SheetsClient {
  String? lastSpreadsheetId;
  String? lastSheetName;
  List<List<Object?>>? lastRows;
  final Map<String, List<List<Object?>>> sheets = {};

  @override
  Future<void> appendRows({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    lastSpreadsheetId = spreadsheetId;
    lastSheetName = sheetName;
    lastRows = rows;
  }

  @override
  Future<void> overwrite({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    lastSpreadsheetId = spreadsheetId;
    lastSheetName = sheetName;
    lastRows = rows;
    sheets[sheetName] = rows;
  }

  @override
  Future<List<List<String>>> read({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final rows = sheets[sheetName] ?? const [];
    return [
      for (final row in rows) [for (final cell in row) cell?.toString() ?? ''],
    ];
  }

  @override
  Future<List<String>> sheetTitles({required String spreadsheetId}) async =>
      sheets.keys.toList();

  @override
  Future<void> addSheets({
    required String spreadsheetId,
    required List<String> titles,
  }) async {
    for (final title in titles) {
      sheets.putIfAbsent(title, () => []);
    }
  }
}

void main() {
  late AppServices services;
  late String adminId;
  late String staffId;
  late DeliveryMan man;

  Future<void> record(
    String barcode, {
    int commission = 2000,
    String? deliveryManId,
  }) {
    return services.delivery.recordCommission(
      barcode: barcode,
      deliveryManId: deliveryManId ?? man.id,
      commission: commission,
      staffUserId: staffId,
    );
  }

  Future<ImportReport> importReceipts(List<List<Object>> rows) =>
      services.reconciliation.importOfficialReceipts(rows);

  setUp(() async {
    services = await AppServices.bootstrap(MemoryStorage());
    final users = await services.users.all();
    adminId = users.firstWhere((u) => u.isAdmin).id;
    staffId = users.firstWhere((u) => !u.isAdmin).id;
    man = await services.deliveryMen.create(
      name: 'U Aung',
      phone: '0912345678',
    );
  });

  group('Delivery commission', () {
    test('1. New barcode commission is saved correctly', () async {
      final result = await services.delivery.recordCommission(
        barcode: '100125',
        deliveryManId: man.id,
        commission: 2000,
        staffUserId: staffId,
      );
      expect(result.record.barcode, '100125');
      expect(result.record.deliveryManId, man.id);
      expect(result.record.commission, 2000);
      expect(result.record.staffUserId, staffId);
      expect(result.record.status, RecordStatus.active);
      expect(result.record.paymentStatus, PaymentStatus.unpaid);
      final inDb = await services.commissions.findByBarcode('100125');
      expect(inDb.id, result.record.id);
    });

    test(
      '2. Duplicate barcode is rejected with existing record info',
      () async {
        await record('100125');
        try {
          await record('100125');
          fail('expected DuplicateBarcodeException');
        } on DuplicateBarcodeException catch (e) {
          expect(e.message, contains('Receipt already recorded'));
          expect(e.message, contains(man.name));
        }
        expect(await services.commissions.all(), hasLength(1));
      },
    );

    test('3. Delivery man selection: inactive man is rejected', () async {
      final m2 = await services.deliveryMen.create(name: 'U Inactive');
      await services.deliveryMen.update(
        DeliveryMan(
          id: m2.id,
          name: 'U Inactive',
          active: false,
          createdAt: m2.createdAt,
        ),
      );
      expect(
        () => record('100200', deliveryManId: m2.id),
        throwsA(isA<ValidationException>()),
      );
      // active man works
      await expectLater(record('100201'), completes);
    });

    test('4. Commission amounts are 1000/2000/3000 and enforced', () async {
      expect(await services.commissions.selectableAmounts(), [
        1000,
        2000,
        3000,
      ]);
      // Shop rule: under 10,000 -> 1,000; 10,000-100,000 -> 2,000.
      expect(await services.commissions.expectedCommission(5000), 1000);
      expect(await services.commissions.expectedCommission(75000), 2000);
      expect(await services.commissions.expectedCommission(125000), 3000);
      await record('B1', commission: 1000);
      await record('B2', commission: 2000);
      await record('B3', commission: 3000);
      expect(await services.commissions.all(), hasLength(3));
      await expectLater(
        record('B4', commission: 2500),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('1000, 2000, 3000'),
          ),
        ),
      );
    });

    test(
      '4b. seedRules rewrites the old default bands, custom bands stay',
      () async {
        Future<CommissionRepository> seeded(
          List<(int, int?, int)> bands,
        ) async {
          final repo = CommissionRepository(MemoryStorage());
          for (final (min, max, amount) in bands) {
            await repo.addRule(
              minAmount: min,
              maxAmount: max,
              commissionAmount: amount,
            );
          }
          await repo.seedRules();
          return repo;
        }

        final migrated = await seeded(const [
          (0, 49999, 1000),
          (50000, 99999, 2000),
          (100000, null, 3000),
        ]);
        expect(await migrated.expectedCommission(5000), 1000);
        expect(await migrated.expectedCommission(35000), 2000);
        expect(await migrated.expectedCommission(125000), 3000);

        final custom = await seeded(const [
          (0, 999, 500),
          (1000, 9999, 1500),
          (10000, null, 2500),
        ]);
        expect(await custom.expectedCommission(500), 500);
      },
    );

    test('5. 10-delivery milestone reward is created once', () async {
      for (var i = 1; i <= 10; i++) {
        await record('D$i', commission: 1000);
      }
      expect(await services.milestones.rewardCountFor(man.id), 1);
      expect(await services.milestones.rewardExists(man.id, 10, 10), isTrue);
      // 11th delivery does not duplicate milestone 10
      await record('D11', commission: 1000);
      expect(await services.milestones.rewardExists(man.id, 10, 10), isTrue);
      expect(await services.milestones.rewardCountFor(man.id), 1);
    });

    test('6. 150-delivery milestones (10 and 150) are created', () async {
      for (var i = 1; i <= 150; i++) {
        await record('E${i.toString().padLeft(4, '0')}', commission: 1000);
      }
      final rewards = await services.milestones.rewards(deliveryManId: man.id);
      final every10 = rewards.where((r) => r.everyN == 10).length;
      final every150 = rewards.where((r) => r.everyN == 150).length;
      expect(every10, 15); // 10,20,...,150
      expect(every150, 1); // 150
      final sum = rewards.fold<int>(0, (s, r) => s + r.rewardAmount);
      expect(sum, 15 * 4000 + 150000);
    });

    test(
      '6b. an admin-edited rule sets the next reward count and amount',
      () async {
        final ten = (await services.milestones.rules()).firstWhere(
          (r) => r.everyN == 10,
        );
        await services.milestones.updateRule(
          MilestoneRule(id: ten.id, everyN: 2, rewardAmount: 5000),
        );

        await record('M1');
        await record('M2');
        final rewards = await services.milestones.rewards(
          deliveryManId: man.id,
        );
        expect(rewards, hasLength(1));
        expect(rewards.single.everyN, 2);
        expect(rewards.single.milestoneCount, 2);
        expect(rewards.single.rewardAmount, 5000);
      },
    );

    test('6c. an inactive rule creates no new rewards', () async {
      final ten = (await services.milestones.rules()).firstWhere(
        (r) => r.everyN == 10,
      );
      await services.milestones.updateRule(
        MilestoneRule(
          id: ten.id,
          everyN: 10,
          rewardAmount: 4000,
          active: false,
        ),
      );

      for (var i = 1; i <= 10; i++) {
        await record('N$i');
      }
      expect(await services.milestones.rewards(deliveryManId: man.id), isEmpty);
    });

    test('6d. a rule the reward engine cannot use is refused', () async {
      final ten = (await services.milestones.rules()).firstWhere(
        (r) => r.everyN == 10,
      );
      await expectLater(
        services.milestones.updateRule(
          MilestoneRule(id: ten.id, everyN: 0, rewardAmount: 4000),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        services.milestones.updateRule(
          MilestoneRule(id: ten.id, everyN: 10, rewardAmount: 0),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Cash control', () {
    test('7. Multiple cash advances are tracked separately', () async {
      await services.cashService.addAdvance(
        amount: 100000,
        note: 'First',
        createdBy: adminId,
      );
      await services.cashService.addAdvance(
        amount: 50000,
        note: 'Second',
        createdBy: adminId,
      );
      final advances = await services.cash.advances();
      expect(advances, hasLength(2));
      expect(advances[0].amount, 100000);
      expect(advances[1].amount, 50000);
      expect(await services.cash.balance(), 150000);
      expect(await services.cash.ledger(), hasLength(2));
    });

    test('8. Commission earned vs paid are tracked separately', () async {
      await record('F1');
      await record('F2');
      await record('F3');
      expect(await services.cashService.commissionEarned(), 6000);
      expect(await services.cashService.commissionPaid(), 0);
      final f1 = await services.commissions.findByBarcode('F1');
      await services.cashService.payCommission(
        recordId: f1.id,
        staffUserId: staffId,
      );
      expect(await services.cashService.commissionEarned(), 6000);
      expect(await services.cashService.commissionPaid(), 2000);
      final updated = await services.commissions.findById(f1.id);
      expect(updated!.paymentStatus, PaymentStatus.paid);
    });

    test('9. Cash balance derives from the ledger', () async {
      await services.cashService.addAdvance(amount: 100000, createdBy: adminId);
      await record('G1');
      final r = await services.commissions.findByBarcode('G1');
      await services.cashService.payCommission(
        recordId: r.id,
        staffUserId: staffId,
      );
      final rew = await services.milestones.rewards();
      if (rew.isNotEmpty) {
        await services.cashService.payMilestoneReward(
          rewardId: rew.first.id,
          staffUserId: staffId,
        );
      }
      final txns = await services.cash.ledger();
      expect(txns, hasLength(2));
      expect(await services.cash.balance(), 100000 - 2000);
      expect(await services.cashService.commissionPaid(), 2000);
    });

    test('10. Monthly closing carries forward and shows difference', () async {
      await services.cashService.addAdvance(amount: 100000, createdBy: adminId);
      await record('H1');
      final r = await services.commissions.findByBarcode('H1');
      await services.cashService.payCommission(
        recordId: r.id,
        staffUserId: staffId,
      );

      final month = monthOfIso(await _todayIso());
      final preview = await services.finance.preview(month);
      expect(preview.openingBalance, 0);
      expect(preview.expectedRemaining, 98000);
      expect(preview.cashReceived, 100000);
      expect(preview.commissionEarned, 2000);
      expect(preview.commissionPaid, 2000);

      final shortage = await services.finance.closeMonth(
        month: month,
        actualCounted: 94000,
        countedBy: 'tester',
      );
      expect(shortage.difference, -4000);
      expect(shortage.isShortage, isTrue);
      // cannot close the same month twice
      await expectLater(
        services.finance.closeMonth(
          month: month,
          actualCounted: 1,
          countedBy: 't',
        ),
        throwsA(isA<ValidationException>()),
      );
      // the counted cash (not the theoretical 98000) carries forward
      final next = await services.finance.preview('2099-01');
      expect(next.openingBalance, 94000);
      expect(next.expectedRemaining, 94000);
    });

    test('11. Reversal: record is kept and barcode can be re-used', () async {
      await record('I1');
      final r = await services.commissions.findByBarcode('I1');
      await services.delivery.reverse(
        recordId: r.id,
        reason: 'wrong barcode',
        byUserId: adminId,
      );
      final reversed = await services.commissions.findById(r.id);
      expect(reversed!.status, RecordStatus.reversed);
      // still exists (never deleted)
      final all = await services.commissions.all();
      expect(all, hasLength(1));
      // barcode free for reuse
      await record('I1');
      final results = await services.commissions.all();
      expect(results, hasLength(2));
      final active = results.where((x) => x.isActive).toList();
      expect(active, hasLength(1));
    });

    test(
      '11a. Correcting the delivery man keeps the record and audits it',
      () async {
        await record('C1');
        final r = await services.commissions.findByBarcode('C1');
        final other = await services.deliveryMen.create(name: 'Daw Hla');
        await services.delivery.changeDeliveryMan(
          recordId: r.id,
          newDeliveryManId: other.id,
        );
        final updated = await services.commissions.findById(r.id);
        expect(updated!.deliveryManId, other.id);
        expect(updated.status, RecordStatus.active);
        expect(await services.commissions.all(), hasLength(1));
      },
    );

    test(
      '11b. Paid commission can be un-paid and re-paid, ledger stays balanced',
      () async {
        await record('P1');
        final r = await services.commissions.findByBarcode('P1');
        await services.cashService.payCommission(
          recordId: r.id,
          staffUserId: staffId,
        );
        expect((await services.commissions.findById(r.id))!.isPaid, isTrue);
        expect(await services.cashService.commissionPaid(), r.commission);
        expect(await services.cashService.balance(), -r.commission);

        await services.cashService.unpayCommission(
          recordId: r.id,
          byUserId: adminId,
        );
        expect((await services.commissions.findById(r.id))!.isPaid, isFalse);
        expect(await services.cashService.commissionPaid(), 0);
        expect(await services.cashService.balance(), 0);

        await services.cashService.payCommission(
          recordId: r.id,
          staffUserId: staffId,
        );
        expect(await services.cashService.commissionPaid(), r.commission);
      },
    );

    test(
      '11c. Reversing a paid commission returns the cash to the box',
      () async {
        await record('R1');
        final r = await services.commissions.findByBarcode('R1');
        await services.cashService.payCommission(
          recordId: r.id,
          staffUserId: staffId,
        );
        await services.delivery.reverse(
          recordId: r.id,
          reason: 'delivery cancelled',
          byUserId: adminId,
        );
        final reversed = await services.commissions.findById(r.id);
        expect(reversed!.status, RecordStatus.reversed);
        expect(reversed.isPaid, isFalse);
        expect(await services.cashService.balance(), 0);
      },
    );

    test(
      '11d. Delivery-board toggle posts commission to the cash ledger',
      () async {
        await record('T1', commission: 2000);
        final r = await services.commissions.findByBarcode('T1');

        final status = await services.delivery.togglePaymentStatus(
          recordId: r.id,
          staffUserId: staffId,
        );
        expect(status, PaymentStatus.paid);
        expect(await services.cashService.commissionPaid(), 2000);
        expect(await services.cashService.balance(), -2000);

        // The finance "Cash & Closing" report must reflect the payment too.
        final today = todayIso();
        final report = await services.finance.report(from: today, to: today);
        expect(report.commissionPaid, 2000);
        expect(report.commissionEarned, 2000);

        // Toggling back must return the cash, not just flip the flag.
        final back = await services.delivery.togglePaymentStatus(
          recordId: r.id,
          staffUserId: staffId,
        );
        expect(back, PaymentStatus.unpaid);
        expect(await services.cashService.commissionPaid(), 0);
        expect(await services.cashService.balance(), 0);
      },
    );

    test(
      '11e. Repair backfills a paid record that has no ledger entry',
      () async {
        await record('F1', commission: 3000);
        final r = await services.commissions.findByBarcode('F1');
        // Simulate legacy data: paid flag set, but no cash entry written.
        await services.commissions.updateRecord(
          r.copyWith(paymentStatus: PaymentStatus.paid, paidAt: nowMs()),
        );
        expect(await services.cashService.commissionPaid(), 0);

        final repaired = await services.cashService
            .repairMissingCommissionPayments();
        expect(repaired, 1);
        expect(await services.cashService.commissionPaid(), 3000);
        // Idempotent: a second run writes nothing more.
        expect(await services.cashService.repairMissingCommissionPayments(), 0);
        expect(await services.cashService.commissionPaid(), 3000);
      },
    );
  });

  group('Reconciliation', () {
    test('Time gap: receipt time vs commission entry', () {
      ReconciliationResult result(String? receiptDate, int? commissionAt) =>
          ReconciliationResult(
            id: 'r1',
            runId: 'run1',
            barcode: 'B1',
            status: ReconciliationStatus.match,
            createdAt: 0,
            receiptDate: receiptDate,
            commissionAt: commissionAt,
          );

      // 09:00 receipt, commission entered 16:30 the same day -> 7h 30m.
      final over = result(
        '2026-08-10 09:00',
        DateTime(2026, 8, 10, 16, 30).millisecondsSinceEpoch,
      );
      expect(over.timeGap, const Duration(hours: 7, minutes: 30));

      final under = result(
        '2026-08-10 09:00',
        DateTime(2026, 8, 10, 10, 0).millisecondsSinceEpoch,
      );
      expect(under.timeGap, const Duration(hours: 1));

      // Receipt export without a Time column would compare against midnight
      // and flag every morning entry, so no gap is reported instead.
      expect(
        result(
          '2026-08-10',
          DateTime(2026, 8, 10, 8).millisecondsSinceEpoch,
        ).timeGap,
        isNull,
      );
      expect(result('2026-08-10 09:00', null).timeGap, isNull);
      expect(
        result(null, DateTime(2026, 8, 10).millisecondsSinceEpoch).timeGap,
        isNull,
      );
    });

    test('12. Official receipt import skips barcodes already stored', () async {
      final report = await importReceipts([
        ['100125', '2026-08-10', 75000],
        ['100126', '2026-08-10', 125000],
        ['100127', '2026-08-10', 35000],
      ]);
      expect(report.imported, 3);
      expect(report.duplicates, 0);
      expect(await services.reconciliation.officialCount(), 3);

      final dupReport = await importReceipts([
        ['100125', '2026-08-11', 75000],
        ['100100', '2026-08-12', 5000],
      ]);
      expect(dupReport.imported, 1);
      expect(dupReport.duplicates, 1);
      expect(dupReport.duplicateBarcodes, ['100125']);
      final matches = await services.receipts.officialByBarcode('100125');
      expect(matches, hasLength(1));
    });

    test('12a. Test lines of one invoice merge into a single receipt', () async {
      final report = await importReceipts([
        ['100200', '2026-08-10', 11000, 'Dr Ko', 'Daw Mya'],
        ['100200', '2026-08-10', 25000, 'Dr Ko', 'Daw Mya'],
        ['100200', '2026-08-10', 8000, '', ''],
      ]);
      expect(report.imported, 1);
      expect(report.duplicates, 0);
      final recs = await services.receipts.officialByBarcode('100200');
      expect(recs, hasLength(1));
      expect(recs.single.totalAmount, 44000);
      expect(recs.single.refer, 'Dr Ko');
      expect(recs.single.patient, 'Daw Mya');
    });

    test('13. Barcode MATCH', () async {
      await importReceipts([
        ['100125', '2026-08-10', 75000, '', 'Daw Mya'],
      ]);
      await record('100125', commission: 2000);
      final run = await services.reconciliation.run(createdBy: adminId);
      expect(run.officialCount, 1);
      expect(run.staffCount, 1);
      expect(run.matchCount, 1);
      expect(run.mismatchCount, 0);
      expect(run.notFoundCount, 0);
      final results = await services.receipts.resultsForRun(run.id);
      expect(results.first.status, ReconciliationStatus.match);
      expect(results.first.expectedCommission, 2000);
      // The patient name travels from the official export to the result row.
      expect(results.first.patient, 'Daw Mya');
      // The commission's own entry time travels with the result, so the
      // detail table can show it (and the time gap) without re-reading the
      // commission records.
      final entered = await services.commissions.findByBarcode('100125');
      expect(results.first.commissionAt, entered.dateTime);
    });

    test('14. Barcode NOT FOUND', () async {
      await record('999999', commission: 2000);
      final run = await services.reconciliation.run(createdBy: adminId);
      expect(run.notFoundCount, 1);
      expect(run.matchCount, 0);
      final results = await services.receipts.resultsForRun(run.id);
      expect(results.first.status, ReconciliationStatus.notFound);
      expect(results.first.receiptAmount, isNull);
      expect(results.first.expectedCommission, isNull);
    });

    test('15. Commission MISMATCH when rules disagree', () async {
      await importReceipts([
        ['100126', '2026-08-10', 125000], // expected 3000
        ['100127', '2026-08-10', 5000], // expected 1000
      ]);
      await record('100126', commission: 2000); // should be 3000
      await record('100127', commission: 2000); // should be 1000
      final run = await services.reconciliation.run(createdBy: adminId);
      expect(run.mismatchCount, 2);
      expect(run.matchCount, 0);
      final results = await services.receipts.resultsForRun(run.id);
      for (final r in results) {
        expect(r.status, ReconciliationStatus.mismatch);
        expect(r.enteredCommission, 2000);
      }
      final byBarcode = results.firstWhere((r) => r.barcode == '100126');
      expect(byBarcode.receiptAmount, 125000);
      expect(byBarcode.expectedCommission, 3000);
    });

    test('16. UNCLAIMED official receipt (no staff record)', () async {
      await importReceipts([
        ['ABC123', '2026-08-10', 60000],
      ]);
      final run = await services.reconciliation.run(createdBy: adminId);
      expect(run.staffCount, 0);
      expect(run.unclaimedCount, 1);
      final results = await services.receipts.resultsForRun(run.id);
      expect(results.first.status, ReconciliationStatus.unclaimed);
    });

    test('17. Duplicate official barcode is flagged', () async {
      for (var i = 0; i < 2; i++) {
        await services.receipts.insertOfficial(
          OfficialReceipt(
            id: 'dup$i',
            barcode: 'DUP1',
            receiptDate: '2026-08-10',
            totalAmount: 75000,
            batchId: 'b',
            importedAt: 1,
          ),
        );
      }
      await record('DUP1', commission: 2000);
      final run = await services.reconciliation.run(createdBy: adminId);
      expect(run.duplicateCount, 1);
      expect(run.matchCount, 0);
      final results = await services.receipts.resultsForRun(run.id);
      final staffRow = results.firstWhere((r) => r.enteredCommission == 2000);
      expect(staffRow.status, ReconciliationStatus.duplicateOfficial);
    });

    test(
      '17c. Duplicate official rows are flagged even when nobody scanned them',
      () async {
        for (var i = 0; i < 2; i++) {
          await services.receipts.insertOfficial(
            OfficialReceipt(
              id: 'dup2$i',
              barcode: 'DUP2',
              receiptDate: '2026-08-10',
              totalAmount: 75000,
              batchId: 'b',
              importedAt: 1,
            ),
          );
        }
        final run = await services.reconciliation.run(createdBy: adminId);
        expect(run.duplicateCount, 2);
        expect(run.unclaimedCount, 0);
        final results = await services.receipts.resultsForRun(run.id);
        expect(results, hasLength(2));
        expect(
          results.every(
            (r) => r.status == ReconciliationStatus.duplicateOfficial,
          ),
          isTrue,
        );
      },
    );

    test('17d. Clearing official receipts also clears reconciliation', () async {
      await importReceipts([
        ['CLR1', '2026-08-10', 75000],
      ]);
      await record('CLR1', commission: 2000);
      await services.reconciliation.run(createdBy: adminId);
      expect(await services.reconciliation.officialCount(), 1);

      await services.receipts.clearOfficial();
      await services.receipts.clearReconciliation();

      expect(await services.reconciliation.officialCount(), 0);
      final (run, results) = await services.reconciliation.latest();
      expect(run, isNull);
      expect(results, isEmpty);
      // Staff records are deliberately kept.
      final kept = await services.commissions.findByBarcode('CLR1');
      expect(kept.barcode, 'CLR1');
    });

    test(
      '17b. An older run reads back with the commission date filled in',
      () async {
        await importReceipts([
          ['OLD1', '2026-08-10 09:00', 75000],
        ]);
        await record('OLD1', commission: 2000);
        final run = await services.reconciliation.run(createdBy: adminId);

        // A run saved before the commission_at column existed has it null; the
        // date is recovered from the commission record when the row is read.
        final results = await services.receipts.resultsForRun(run.id);
        final entered = await services.commissions.findByBarcode('OLD1');
        // Simulate the old row: null the column the way an old build left it.
        await services.storage.update(
          'reconciliation_results',
          {'id': results.first.id},
          {'commission_at': null},
        );
        final backfilled = await services.receipts.resultsForRun(run.id);
        expect(backfilled.first.commissionAt, entered.dateTime);
        expect(backfilled.first.timeGap, isNotNull);
      },
    );
  });

  group('Google Sheets', () {
    test(
      '18. Commission and reconciliation rows are prepared/sent via client',
      () async {
        final fake = FakeSheetsClient();
        services.sheets.client = fake;
        services.sheets.config = const GoogleSheetsConfig(
          spreadsheetId: 'spreadsheet-123',
          sheetName: 'CommissionRecords',
          serviceAccountJson: '{"type":"service_account"}',
        );
        await record('J1', commission: 1000);
        await record('J2', commission: 3000);

        await services.sheets.syncCommissionRecords();
        expect(fake.lastSpreadsheetId, 'spreadsheet-123');
        expect(fake.lastSheetName, 'CommissionRecords');
        final rows = fake.lastRows!;
        expect(rows.first, GoogleSheetsService.commissionHeaders);
        expect(rows, hasLength(3));
        final j1 = rows.firstWhere((r) => r[1] == 'J1');
        expect(j1[4], 1000);
        expect(j1[6], staffId);
        expect(j1[7], RecordStatus.active.name);

        await importReceipts([
          ['J2', '2026-08-10', 125000],
        ]);
        final run = await services.reconciliation.run(createdBy: adminId);
        final results = await services.receipts.resultsForRun(run.id);
        fake.lastRows = null;
        await services.sheets.syncReconciliation(
          runId: run.id,
          results: results,
        );
        expect(fake.lastRows!.first, GoogleSheetsService.reconciliationHeaders);
        final j2Row = fake.lastRows!.firstWhere((r) => r[0] == 'J2');
        expect(j2Row[1], '--'); // patient (not imported)
        expect(j2Row[2], 125000); // receipt amount
        expect(j2Row[3], '--'); // refer (not imported)
        expect(j2Row[5], 3000); // entered
        expect(j2Row[6], 3000); // expected  (125000 -> 3000)
        expect(j2Row[7], 'MATCH');
      },
    );

    test(
      '19. Backup then restore round-trips all data through the sheet',
      () async {
        final fake = FakeSheetsClient();
        services.sheets.client = fake;
        services.sheets.config = const GoogleSheetsConfig(
          spreadsheetId: 'spreadsheet-123',
          serviceAccountJson: '{"type":"service_account"}',
        );

        await record('BK1', commission: 2000);
        await services.cashService.addAdvance(
          amount: 50000,
          createdBy: adminId,
        );

        final backup = await services.sheets.backupAll();
        expect(backup.tables, backupTables.length);
        expect(fake.sheets['commission_records']!.first.first, 'id');

        // Credentials must never be uploaded.
        final settingsRows = fake.sheets['commission_settings'] ?? const [];
        expect(
          settingsRows
              .skip(1)
              .any((r) => r.first.toString().startsWith('sheets.')),
          isFalse,
        );

        // Simulate a total local data loss.
        for (final table in backupTables) {
          await services.storage.clear(table.name);
        }
        expect(await services.commissions.all(), isEmpty);

        final restore = await services.sheets.restoreAll();
        expect(restore.rows, backup.rows);

        final records = await services.commissions.all();
        expect(records, hasLength(1));
        expect(records.first.barcode, 'BK1');
        expect(records.first.commission, 2000);
        expect(records.first.deliveryManId, man.id);
        expect(await services.deliveryMen.all(), hasLength(1));
        expect(await services.cashService.balance(), 50000);
      },
    );

    test('Unconfigured client throws SheetsNotConfiguredException', () async {
      services.sheets.client = UnconfiguredSheetsClient();
      expect(
        services.sheets.syncCommissionRecords(),
        throwsA(isA<SheetsNotConfiguredException>()),
      );
    });
  });

  group('OfficialReceiptParser', () {
    test('reads receipt-software export with header on row 3', () {
      const rows = [
        ['ACME Receipt Report', ''],
        ['', ''],
        ['Invoice', 'Date', 'Time', 'Patient', 'Refer', 'Net amt'],
        ['100125', '10/08/2026', '14:30', 'Daw Mya', 'OK', '75,000'],
        ['100126', '10/08/2026', '14:32', 'U Aung', 'JS', '125000'],
      ];
      final parsed = OfficialReceiptParser.parse('export.xlsx', rows);
      expect(parsed, hasLength(2));
      expect(parsed[0], [
        '100125',
        '2026-08-10 14:30',
        75000,
        'OK',
        'Daw Mya',
      ]);
      expect(parsed[1], [
        '100126',
        '2026-08-10 14:32',
        125000,
        'JS',
        'U Aung',
      ]);
    });

    test('prefers "Patient Name" over a "Patient ID" column', () {
      const rows = [
        ['Invoice', 'Date', 'Patient ID', 'Patient Name', 'Net amt'],
        ['100125', '10/08/2026', 'P-001', 'Daw Mya', '75,000'],
      ];
      final parsed = OfficialReceiptParser.parse('export.csv', rows);
      expect(parsed.single[4], 'Daw Mya');
    });

    test('supports "invoice no" and "refer by" variant headers', () {
      const rows = [
        ['Invoice No', 'Refer By', 'Date', 'Time', 'Net amt'],
        ['A0123', 'Moe', '2026/08/10', '2:35 PM', '1,000'],
      ];
      final parsed = OfficialReceiptParser.parse('export.csv', rows);
      expect(parsed, hasLength(1));
      expect(parsed.first, ['A0123', '2026-08-10 14:35', 1000, 'Moe', '']);
    });

    test('skips totals footer rows but keeps data rows', () {
      const rows = [
        ['Invoice', 'Date', 'Refer', 'Net amt'],
        ['100125', '10/08/2026', 'OK', '75,000'],
        ['100126', '10/08/2026', 'JS', '125000'],
        ['', '', 'Grand Total:', '200,000'],
      ];
      final parsed = OfficialReceiptParser.parse('export.xlsx', rows);
      expect(parsed, hasLength(2));
    });

    test('prefers the invoice column over a serial "No" column', () {
      const rows = [
        ['No', 'Invoice', 'Date', 'Time', 'Refer By', 'Net amt'],
        ['1', '100125', '10/08/2026', '14:30', 'OK', '75,000'],
      ];
      final parsed = OfficialReceiptParser.parse('export.xlsx', rows);
      expect(parsed, hasLength(1));
      expect(parsed.first.first, '100125');
    });

    test(
      'falls back to a plain "No" column when nothing else names the receipt',
      () {
        const rows = [
          ['No', 'Date', 'Net amt'],
          ['100125', '10/08/2026', '75,000'],
        ];
        final parsed = OfficialReceiptParser.parse('export.csv', rows);
        expect(parsed, hasLength(1));
        expect(parsed.first.first, '100125');
      },
    );

    test('official receipts keep the refer and patient columns', () async {
      final report = await services.reconciliation.importOfficialReceipts([
        ['100999', '2026-08-10', 75000, 'Dr Ko', 'Daw Mya'],
      ]);
      expect(report.imported, 1);
      final recs = await services.receipts.officialByBarcode('100999');
      expect(recs.single.refer, 'Dr Ko');
      expect(recs.single.patient, 'Daw Mya');
    });
  });

  group('Excel export', () {
    test('20. buildExcelBytes produces a readable cash-advances workbook', () {
      final bytes = buildExcelBytes(
        sheetName: 'Cash Advances',
        headers: const ['Date', 'Amount (MMK)', 'Note'],
        rows: const [
          ['2026-08-10', 100000, 'Owner advance'],
          ['2026-08-11', 50000, ''],
        ],
      );

      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables['Cash Advances'];
      expect(sheet, isNotNull);
      final rows = sheet!.rows;
      expect(rows, hasLength(3)); // header + 2 data rows
      expect(rows[0].map((c) => c?.value.toString()).toList(), [
        'Date',
        'Amount (MMK)',
        'Note',
      ]);
      expect(rows[1][0]?.value.toString(), '2026-08-10');
      expect((rows[1][1]!.value as IntCellValue).value, 100000);
      expect(rows[1][2]?.value.toString(), 'Owner advance');
      expect((rows[2][1]!.value as IntCellValue).value, 50000);
    });
  });
}

Future<String> _todayIso() async {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}
