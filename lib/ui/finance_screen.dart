// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/exceptions.dart';
import '../domain/ids.dart';
import '../domain/period.dart';
import '../domain/services/finance_service.dart';
import 'common.dart';
import 'excel_export.dart';

enum _PeriodMode { day, month }

/// One screen for cash reporting: ledger, cash advances, per-delivery-man
/// performance, and monthly closing (with carry-forward), filtered by a single
/// day or a whole month.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  _PeriodMode _mode = _PeriodMode.month;
  String _day = todayIso();
  String _month = monthOfIso(todayIso());
  final _actual = TextEditingController();

  bool _loading = true;
  FinanceReport? _report;
  MonthlyClosing? _closing;
  List<MonthlyClosing> _closings = [];

  String get _from => _mode == _PeriodMode.day ? _day : monthFirstDay(_month);
  String get _to => _mode == _PeriodMode.day ? _day : monthLastDay(_month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.of(context);
    final report = await s.finance.report(from: _from, to: _to);
    MonthlyClosing? closing;
    var closings = <MonthlyClosing>[];
    if (_mode == _PeriodMode.month) {
      closing = await s.finance.closingForMonth(_month);
      closings = await s.finance.closings();
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _closing = closing;
      _closings = closings;
      _loading = false;
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_day) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _day = formatIso(picked);
      _loading = true;
    });
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _MonthPickerDialog(initial: _month),
    );
    if (picked == null) return;
    setState(() {
      _month = picked;
      _loading = true;
    });
    _load();
  }

  Future<void> _closeMonth() async {
    final s = AppScope.of(context);
    final actual = int.tryParse(_actual.text.trim()) ?? 0;
    try {
      final c = await s.finance.closeMonth(
        month: _month,
        actualCounted: actual,
        countedBy: s.auth.requireUser().name,
      );
      showMessage(context, 'Month closed. Difference: ${fmtMMK(c.difference)}');
      _actual.clear();
      _load();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    }
  }

  Future<void> _exportAdvances() async {
    final advances = _report?.advances ?? const [];
    if (advances.isEmpty) {
      showMessage(context, 'No cash advances in this period', error: true);
      return;
    }
    try {
      final saved = await exportToExcel(
        fileName: 'cash_advances_${_from}_$_to.xlsx',
        sheetName: 'Cash Advances',
        headers: const [
          'Date',
          'Amount (MMK)',
          'Note',
          'Recorded by',
          'Created at',
        ],
        rows: [
          for (final a in advances)
            [a.date, a.amount, a.note, a.createdBy, fmtDate(a.createdAt)],
        ],
      );
      if (saved) {
        showMessage(context, 'Exported ${advances.length} cash advances');
      }
    } on Exception catch (e) {
      showMessage(context, 'Export failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return PageScaffold(
      title: 'Cash & Closing',
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _filterCard(),
          if (_loading || r == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _summary(r),
            if (_mode == _PeriodMode.month) _closingCard(r),
            const SectionTitle('Per delivery man'),
            if (r.performance.isEmpty)
              const EmptyState(message: 'No deliveries in this period.')
            else
              for (final p in r.performance) _performanceTile(p),
            const SectionTitle('Ledger entries'),
            if (r.ledger.isEmpty)
              const EmptyState(message: 'No cash movement in this period.')
            else
              for (final t in r.ledger) _ledgerTile(t),
            _advancesHeader(r.advances.isEmpty),
            if (r.advances.isEmpty)
              const EmptyState(message: 'No advances in this period.')
            else
              for (final a in r.advances) _advanceTile(a),
          ],
        ],
      ),
    );
  }

  Widget _filterCard() {
    final label = _mode == _PeriodMode.day
        ? _dayLabel(_day)
        : monthLabel(_month);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_PeriodMode>(
                segments: const [
                  ButtonSegment(
                    value: _PeriodMode.day,
                    label: Text('Day'),
                    icon: Icon(Icons.today),
                  ),
                  ButtonSegment(
                    value: _PeriodMode.month,
                    label: Text('Month'),
                    icon: Icon(Icons.calendar_month),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                    _loading = true;
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(
                _mode == _PeriodMode.day ? 'Selected day' : 'Selected month',
              ),
              subtitle: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.edit),
              onTap: _mode == _PeriodMode.day ? _pickDay : _pickMonth,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(FinanceReport r) {
    return AutoGrid(
      childAspectRatio: 2.2,
      children: [
        statCard(
          context,
          'Remaining cash',
          fmtMMK(r.closingBalance),
          color: Colors.teal,
        ),
        statCard(context, 'Carried forward', fmtMMK(r.openingBalance)),
        statCard(context, 'Cash from owner', fmtMMK(r.cashReceived)),
        statCard(context, 'Commission earned', fmtMMK(r.commissionEarned)),
        statCard(context, 'Commission paid', fmtMMK(r.commissionPaid)),
        statCard(context, 'Rewards paid', fmtMMK(r.rewardsPaid)),
        statCard(context, 'Other payments', fmtMMK(r.otherPayments)),
        statCard(context, 'Successful deliveries', '${r.deliveries}'),
      ],
    );
  }

  Widget _advancesHeader(bool empty) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Cash advances',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: Colors.teal),
            ),
          ),
          TextButton.icon(
            onPressed: empty ? null : _exportAdvances,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('Excel'),
          ),
        ],
      ),
    );
  }

  Widget _closingCard(FinanceReport r) {
    final closed = _closing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.balance),
                const SizedBox(width: 8),
                Text(
                  'Monthly closing · ${monthLabel(_month)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _kv('Carried forward', fmtMMK(r.openingBalance)),
            _kv('Expected remaining', fmtMMK(r.closingBalance), bold: true),
            const Divider(),
            if (closed != null) ...[
              _kv('Actual counted', fmtMMK(closed.actualCounted)),
              _kv(
                'Difference',
                '${closed.difference >= 0 ? '+' : ''}${fmtMMK(closed.difference)}',
                bold: true,
                color: closed.difference == 0
                    ? Colors.green
                    : closed.isShortage
                    ? Colors.red
                    : Colors.orange,
              ),
              const SizedBox(height: 4),
              Text(
                'Closed by ${closed.countedBy}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              TextField(
                controller: _actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Actual cash counted (MMK)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _closeMonth,
                child: const Text('CLOSE MONTH'),
              ),
            ],
            if (_closings.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const Text(
                'Previous closings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final c in _closings)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(monthLabel(c.month)),
                  subtitle: Text(
                    'Expected ${fmtMMK(c.expectedRemaining)} · Actual ${fmtMMK(c.actualCounted)}',
                  ),
                  trailing: Text(
                    '${c.difference >= 0 ? '+' : ''}${fmtMMK(c.difference)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: c.difference == 0
                          ? Colors.green
                          : c.isShortage
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _performanceTile(DeliveryManPerformance p) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(p.name),
        subtitle: Text('${p.deliveries} deliveries'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtMMK(p.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'comm ${fmtMMK(p.commission)} + rw ${fmtMMK(p.rewards)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerTile(CashTransaction t) {
    return ListTile(
      dense: true,
      leading: Icon(
        t.isIncoming ? Icons.south_west : Icons.north_east,
        color: t.isIncoming ? Colors.green : Colors.red,
      ),
      title: Text(t.note.isEmpty ? t.type.name : t.note),
      subtitle: Text('${t.date} · ${t.type.name}'),
      trailing: Text(
        t.isIncoming ? '+${fmtMMK(t.amount)}' : fmtMMK(t.amount),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: t.isIncoming ? Colors.green : Colors.red,
        ),
      ),
    );
  }

  Widget _advanceTile(CashAdvance a) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.payments),
      title: Text(a.note.isEmpty ? 'Advance ${a.date}' : a.note),
      subtitle: Text(a.date),
      trailing: Text(
        '+${fmtMMK(a.amount)}',
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _dayLabel(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final String initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final parts = widget.initial.split('-');
    _year = int.parse(parts[0]);
    _month = int.parse(parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final nowYear = DateTime.now().year;
    final years = [for (var y = nowYear - 5; y <= nowYear + 1; y++) y];
    return AlertDialog(
      title: const Text('Select month'),
      content: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(monthName(m))),
              ],
              onChanged: (v) => setState(() => _month = v ?? _month),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [
                for (final y in years)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) => setState(() => _year = v ?? _year),
            ),
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
            '$_year-${_month.toString().padLeft(2, '0')}',
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
