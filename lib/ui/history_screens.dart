// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/exceptions.dart';
import 'common.dart';
import 'trip_history_screen.dart';

/// Keeps the deliveries of [deliveryManId] that fall inside [range]; both ends
/// of the range include their whole calendar day.
List<CommissionRecord> filterDeliveries(
  List<CommissionRecord> records, {
  String? deliveryManId,
  DateTimeRange? range,
}) {
  final start = range == null
      ? null
      : DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        ).millisecondsSinceEpoch;
  final end = range == null
      ? null
      : DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch;
  return records.where((r) {
    if (deliveryManId != null && r.deliveryManId != deliveryManId) return false;
    if (start == null || end == null) return true;
    return r.dateTime >= start && r.dateTime < end;
  }).toList();
}

class DeliveryHistoryScreen extends StatefulWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  List<CommissionRecord> _records = [];
  Map<String, PrintedReceipt> _receipts = {};
  List<DeliveryMan> _men = [];
  String? _manId;
  DateTimeRange? _range;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = AppScope.of(context);
      final user = services.auth.requireUser();
      final records = await services.commissions.all(
        staffUserId: user.isAdmin ? null : user.id,
      );
      // One request for all men; per-record lookups are very slow over the
      // office server compared with the local database.
      final men = await services.deliveryMen.all();
      final names = {for (final m in men) m.id: m.name};
      final named = [
        for (final r in records)
          r.copyWith(
            deliveryManName: names[r.deliveryManId] ?? r.deliveryManId,
          ),
      ];
      final receipts = receiptDetailsByBarcode(
        await services.printedReceipts.byBarcode(),
        await services.receipts.officialReceiptsByBarcode(),
      );
      if (!mounted) return;
      setState(() {
        _records = named;
        _receipts = receipts;
        _men = men;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: _manId,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Delivery man',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final man in _men)
                  DropdownMenuItem(value: man.id, child: Text(man.name)),
              ],
              onChanged: (v) => setState(() => _manId = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                _range == null
                    ? 'All dates'
                    : '${fmtDay(_range!.start.millisecondsSinceEpoch)}'
                          ' – ${fmtDay(_range!.end.millisecondsSinceEpoch)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (_range != null)
            IconButton(
              tooltip: 'Clear date filter',
              onPressed: () => setState(() => _range = null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterDeliveries(
      _records,
      deliveryManId: _manId,
      range: _range,
    );
    return PageScaffold(
      title: 'Delivery History',
      body: Column(
        children: [
          _filters(),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? EmptyState(message: _error!, onRetry: _load)
                  : filtered.isEmpty
                  ? EmptyState(
                      message: _records.isEmpty
                          ? 'No deliveries recorded yet.'
                          : 'No deliveries match these filters.',
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        final receipt = _receipts[r.barcode];
                        final receiptLine = receipt?.summary ?? '';
                        return ListTile(
                          onTap: () => showAuditTrail(context, r.id),
                          leading: const Icon(Icons.qr_code),
                          title: Text(
                            '${r.barcode} · ${r.deliveryManName ?? ''}',
                          ),
                          subtitle: Text(
                            receiptLine.isEmpty
                                ? fmtDate(r.dateTime)
                                : '${fmtDate(r.dateTime)}\n$receiptLine',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: receiptLine.isNotEmpty,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                fmtMMK(r.commission),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                r.status.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: r.isActive ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CommissionHistoryScreen extends StatefulWidget {
  const CommissionHistoryScreen({super.key});

  @override
  State<CommissionHistoryScreen> createState() =>
      _CommissionHistoryScreenState();
}

class _CommissionHistoryScreenState extends State<CommissionHistoryScreen> {
  List<CommissionRecord> _records = [];
  Map<String, PrintedReceipt> _receipts = {};
  List<MilestoneReward> _rewards = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = AppScope.of(context);
      final records = await services.commissions.all();
      final rewards = await services.milestones.rewards();
      // One request for all men instead of one per record/reward; each lookup
      // is a full round trip when the data lives on the office server.
      final men = await services.deliveryMen.all();
      final names = {for (final m in men) m.id: m.name};
      final receipts = receiptDetailsByBarcode(
        await services.printedReceipts.byBarcode(),
        await services.receipts.officialReceiptsByBarcode(),
      );
      if (!mounted) return;
      setState(() {
        _records = [
          for (final r in records)
            r.copyWith(
              deliveryManName: names[r.deliveryManId] ?? r.deliveryManId,
            ),
        ];
        _rewards = [
          for (final rw in rewards)
            rw.copyWith(
              deliveryManName: names[rw.deliveryManId] ?? rw.deliveryManId,
            ),
        ];
        _receipts = receipts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Opens the GPS route kept for this receipt's delivery.
  void _showTrip(CommissionRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripHistoryScreen(
          barcode: record.barcode,
          deliveryManName: record.deliveryManName ?? '',
        ),
      ),
    );
  }

  Future<void> _correct(CommissionRecord record) async {
    final services = AppScope.of(context);
    final active = await services.deliveryMen.all(includeInactive: false);
    final options = <DeliveryMan>[...active];
    if (!options.any((m) => m.id == record.deliveryManId)) {
      options.insert(
        0,
        DeliveryMan(
          id: record.deliveryManId,
          name: '${record.deliveryManName ?? record.deliveryManId} (inactive)',
          active: false,
          createdAt: 0,
        ),
      );
    }
    if (!mounted) return;
    final result = await showDialog<_Correction>(
      context: context,
      builder: (ctx) => _CorrectDialog(record: record, men: options),
    );
    if (result == null) return;
    if (!await askDailyPin(
      context,
      reason: 'Correct transaction ${record.barcode}?',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      final userId = services.auth.requireUser().id;
      if (result.deliveryManId != record.deliveryManId) {
        await services.delivery.changeDeliveryMan(
          recordId: record.id,
          newDeliveryManId: result.deliveryManId,
        );
      }
      if (result.paid != record.isPaid) {
        if (result.paid) {
          await services.cashService.payCommission(
            recordId: record.id,
            staffUserId: userId,
          );
        } else {
          await services.cashService.unpayCommission(
            recordId: record.id,
            byUserId: userId,
          );
        }
      }
      showMessage(context, 'Correction saved');
      _load();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    }
  }

  Future<void> _delete(CommissionRecord record) async {
    final reason = await deleteReasonDialog(context);
    if (reason == null) return;
    if (!await askDailyPin(
      context,
      reason: 'Delete transaction ${record.barcode}?',
    )) {
      return;
    }
    final services = AppScope.of(context);
    try {
      await services.delivery.reverse(
        recordId: record.id,
        reason: reason,
        byUserId: services.auth.requireUser().id,
      );
      showMessage(context, 'Transaction deleted');
      _load();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    }
  }

  Future<void> _pay(CommissionRecord record) async {
    if (!await confirmMarkPaid(
      context,
      label: '${record.deliveryManName ?? record.deliveryManId} · commission',
      amount: record.commission,
    )) {
      return;
    }
    if (!mounted) return;
    final services = AppScope.of(context);
    try {
      await services.cashService.payCommission(
        recordId: record.id,
        staffUserId: services.auth.requireUser().id,
      );
      showMessage(
        context,
        'Cash payment recorded (-${fmtMMK(record.commission)})',
      );
      _load();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    }
  }

  Future<void> _payReward(MilestoneReward reward) async {
    final services = AppScope.of(context);
    try {
      await services.cashService.payMilestoneReward(
        rewardId: reward.id,
        staffUserId: services.auth.requireUser().id,
      );
      showMessage(context, 'Reward paid (-${fmtMMK(reward.rewardAmount)})');
      _load();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Commission History',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? EmptyState(message: _error!, onRetry: _load)
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Commissions'),
                      Tab(text: 'Milestone Rewards'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView.builder(
                          itemCount: _records.length,
                          itemBuilder: (ctx, i) {
                            final r = _records[i];
                            final receiptLine =
                                _receipts[r.barcode]?.summary ?? '';
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: InkWell(
                                onTap: () => showAuditTrail(context, r.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${r.barcode} · ${r.deliveryManName ?? ''}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            fmtMMK(r.commission),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${fmtDate(r.dateTime)} · ${r.staffUserId}\n${r.isActive ? '${r.status.name} · ${r.paymentStatus.name}' : 'deleted'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (receiptLine.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            receiptLine,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                      if (!r.isActive &&
                                          (r.reversalReason?.isNotEmpty ??
                                              false))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            'Reason: ${r.reversalReason}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.red),
                                          ),
                                        ),
                                      if (r.isActive)
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () => _showTrip(r),
                                              icon: const Icon(
                                                Icons.route,
                                                size: 16,
                                              ),
                                              label: const Text('Trip'),
                                            ),
                                            if (!r.isPaid)
                                              TextButton(
                                                onPressed: () => _pay(r),
                                                child: const Text('PAY'),
                                              ),
                                            TextButton.icon(
                                              onPressed: () => _correct(r),
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 16,
                                              ),
                                              label: const Text('Correct'),
                                            ),
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                              onPressed: () => _delete(r),
                                              icon: const Icon(
                                                Icons.delete,
                                                size: 16,
                                              ),
                                              label: const Text('Delete'),
                                            ),
                                          ],
                                        )
                                      else
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => _showTrip(r),
                                            icon: const Icon(
                                              Icons.route,
                                              size: 16,
                                            ),
                                            label: const Text('Trip'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        ListView.builder(
                          itemCount: _rewards.length,
                          itemBuilder: (ctx, i) {
                            final rw = _rewards[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: InkWell(
                                onTap: () => showAuditTrail(context, rw.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.emoji_events,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${rw.deliveryManName ?? ''} · ${rw.label}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${fmtDate(rw.createdAt)} · payment: ${rw.paymentStatus.name}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            fmtMMK(rw.rewardAmount),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (rw.paymentStatus ==
                                              PaymentStatus.unpaid)
                                            TextButton(
                                              onPressed: () => _payReward(rw),
                                              child: const Text('PAY'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Outcome of the correction dialog: the (possibly unchanged) delivery man and
/// payment status chosen by the user.
class _Correction {
  const _Correction({required this.deliveryManId, required this.paid});
  final String deliveryManId;
  final bool paid;
}

class _CorrectDialog extends StatefulWidget {
  const _CorrectDialog({required this.record, required this.men});

  final CommissionRecord record;
  final List<DeliveryMan> men;

  @override
  State<_CorrectDialog> createState() => _CorrectDialogState();
}

class _CorrectDialogState extends State<_CorrectDialog> {
  late String _deliveryManId = widget.record.deliveryManId;
  late bool _paid = widget.record.isPaid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correct transaction'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Barcode ${widget.record.barcode}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _deliveryManId,
            decoration: const InputDecoration(
              labelText: 'Delivery man',
              border: OutlineInputBorder(),
            ),
            items: widget.men
                .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                .toList(),
            onChanged: (v) =>
                setState(() => _deliveryManId = v ?? _deliveryManId),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Paid'),
            subtitle: const Text(
              'Changing this keeps the cash ledger balanced.',
            ),
            value: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _Correction(deliveryManId: _deliveryManId, paid: _paid),
          ),
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
