// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/exceptions.dart';
import '../domain/ids.dart';
import 'cash_advance_editor.dart';
import 'common.dart';
import 'excel_export.dart';

class CashAdvanceScreen extends StatefulWidget {
  const CashAdvanceScreen({super.key});

  @override
  State<CashAdvanceScreen> createState() => _CashAdvanceScreenState();
}

class _CashAdvanceScreenState extends State<CashAdvanceScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();
  bool _saving = false;
  List<CashAdvance> _advances = [];
  bool _loadingAdvances = true;

  @override
  void initState() {
    super.initState();
    _loadAdvances();
  }

  Future<void> _loadAdvances() async {
    final advances = await AppScope.of(context).cash.advances();
    if (!mounted) return;
    setState(() {
      _advances = advances;
      _loadingAdvances = false;
    });
  }

  Future<void> _edit(CashAdvance advance) async {
    if (await editCashAdvance(context, advance)) _loadAdvances();
  }

  Future<void> _delete(CashAdvance advance) async {
    if (await deleteCashAdvance(context, advance)) _loadAdvances();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date =
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final s = AppScope.of(context);
      await s.cashService.addAdvance(
        amount: amount,
        note: _note.text.trim(),
        date: _date,
        createdBy: s.auth.requireUser().id,
      );
      showMessage(context, 'Cash advance recorded: +${fmtMMK(amount)}');
      _amount.clear();
      _note.clear();
      _loadAdvances();
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportAll() async {
    final s = AppScope.of(context);
    try {
      final advances = await s.cash.advances();
      if (advances.isEmpty) {
        showMessage(context, 'No cash advances to export', error: true);
        return;
      }
      final saved = await exportToExcel(
        fileName: 'cash_advances_all.xlsx',
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
    return PageScaffold(
      title: 'Cash Advance',
      actions: [
        IconButton(
          tooltip: 'Export all advances (Excel)',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: _exportAll,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text(
                    'Example: 10/08/2026 Owner gives 100,000 MMK to staff as working cash.\nEvery advance stays separately identifiable.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Advance date'),
                    trailing: Text(
                      reformatDate(_date),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: _pickDate,
                  ),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (MMK)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note (e.g. Owner cash advance 10/08/2026)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('RECORD CASH ADVANCE'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Recorded advances',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          if (_loadingAdvances)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_advances.isEmpty)
            const EmptyState(message: 'No cash advances recorded yet.')
          else
            for (final advance in _advances) _advanceTile(advance),
        ],
      ),
    );
  }

  Widget _advanceTile(CashAdvance advance) {
    return ListTile(
      leading: const Icon(Icons.payments),
      title: Text(
        advance.note.isEmpty ? 'Advance ${advance.date}' : advance.note,
      ),
      subtitle: Text(reformatDate(advance.date)),
      onTap: () => _edit(advance),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+${fmtMMK(advance.amount)}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            tooltip: 'Correct advance',
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _edit(advance),
          ),
          IconButton(
            tooltip: 'Delete advance',
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: () => _delete(advance),
          ),
        ],
      ),
    );
  }
}
