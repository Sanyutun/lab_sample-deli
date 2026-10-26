import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/exceptions.dart';
import '../domain/period.dart';
import 'common.dart';

/// Lets an admin correct an existing cash advance (amount, date or note).
/// Saving is gated by the Admin PIN, and the linked ledger entry is updated so
/// cash balances and reports follow the correction.
///
/// Returns true when the advance was saved.
Future<bool> editCashAdvance(
  BuildContext context,
  CashAdvance advance,
) async {
  final draft = await showDialog<_AdvanceDraft>(
    context: context,
    builder: (_) => _CashAdvanceEditDialog(advance: advance),
  );
  if (draft == null || !context.mounted) return false;
  if (draft.amount == advance.amount &&
      draft.date == advance.date &&
      draft.note == advance.note) {
    showMessage(context, 'No changes to save');
    return false;
  }

  final changes = <String>[
    if (draft.amount != advance.amount)
      'amount ${fmtMMK(advance.amount)} to ${fmtMMK(draft.amount)}',
    if (draft.date != advance.date)
      'date ${reformatDate(advance.date)} to ${reformatDate(draft.date)}',
    if (draft.note != advance.note) 'note',
  ];
  final approved = await askAdminPin(
    context,
    reason: 'Correct this cash advance (${changes.join(', ')})?',
  );
  if (!approved || !context.mounted) return false;

  final services = AppScope.of(context);
  try {
    await services.cashService.updateAdvance(
      id: advance.id,
      amount: draft.amount,
      date: draft.date,
      note: draft.note,
      updatedBy: services.auth.requireUser().id,
    );
    if (!context.mounted) return true;
    showMessage(context, 'Cash advance corrected');
    return true;
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return false;
  }
}

/// Deletes a cash advance after confirmation and the Admin PIN. The cash ledger
/// gets a compensating entry instead of losing the original movement, so the
/// balance stays correct and the history remains auditable.
///
/// Returns true when the advance was deleted.
Future<bool> deleteCashAdvance(
  BuildContext context,
  CashAdvance advance,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete cash advance?'),
      content: Text(
        'Delete ${fmtMMK(advance.amount)} on ${reformatDate(advance.date)}'
        '${advance.note.isEmpty ? '' : ' (${advance.note})'}?\n\n'
        'The cash ledger will be corrected; the audit log keeps a record.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final approved = await askAdminPin(
    context,
    reason:
        'Delete the ${fmtMMK(advance.amount)} cash advance on '
        '${reformatDate(advance.date)}?',
  );
  if (!approved || !context.mounted) return false;

  final services = AppScope.of(context);
  try {
    await services.cashService.deleteAdvance(
      id: advance.id,
      byUserId: services.auth.requireUser().id,
    );
    if (!context.mounted) return true;
    showMessage(context, 'Cash advance deleted');
    return true;
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return false;
  }
}

class _AdvanceDraft {
  const _AdvanceDraft({
    required this.amount,
    required this.date,
    required this.note,
  });

  final int amount;
  final String date;
  final String note;
}

class _CashAdvanceEditDialog extends StatefulWidget {
  const _CashAdvanceEditDialog({required this.advance});

  final CashAdvance advance;

  @override
  State<_CashAdvanceEditDialog> createState() => _CashAdvanceEditDialogState();
}

class _CashAdvanceEditDialogState extends State<_CashAdvanceEditDialog> {
  late final _amount = TextEditingController(text: '${widget.advance.amount}');
  late final _note = TextEditingController(text: widget.advance.note);
  late String _date = widget.advance.date;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = formatIso(picked));
  }

  void _save() {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount', error: true);
      return;
    }
    Navigator.pop(
      context,
      _AdvanceDraft(amount: amount, date: _date, note: _note.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correct cash advance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
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
              autofocus: true,
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
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}
