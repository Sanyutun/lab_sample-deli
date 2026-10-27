import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../print/print_spool_watcher.dart';

String fmtMMK(int amount) => '${NumberFormat('#,###').format(amount)} MMK';

String fmtDate(int ms) =>
    DateFormat('dd/MM/yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));

String fmtDay(int ms) =>
    DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// Shows a stored `yyyy-MM-dd` date as `dd/MM/yyyy`.
String reformatDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('dd/MM/yyyy').format(d);
}

/// One `Label: value` line per field read off a printed receipt, skipping the
/// ones the job did not carry.
List<Widget> receiptFieldLines(PrintedInvoice printed) {
  final fields = <String, String?>{
    'Name': printed.name,
    'Age/Sex': printed.ageSex,
    'Refer': printed.refer,
    'Date': printed.date,
    'Total Amount': printed.totalAmount,
  };
  return [
    for (final entry in fields.entries)
      if (entry.value != null && entry.value!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  '${entry.key}:',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              Expanded(
                child: Text(
                  entry.value!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
  ];
}

Widget statCard(
  BuildContext context,
  String label,
  String value, {
  Color? color,
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Color statusColor(String status) => switch (status) {
  'MATCH' => Colors.green,
  'MISMATCH' => Colors.orange,
  'NOT FOUND' => Colors.red,
  'DUPLICATE' => Colors.purple,
  'UNCLAIMED' => Colors.blueGrey,
  'COMPLETE' => Colors.green,
  'INCOMPLETE' => Colors.orange,
  _ when status.startsWith('OVER') => Colors.red,
  _ => Colors.grey,
};

Widget statusChip(String status) => Chip(
  label: Text(
    status,
    style: const TextStyle(color: Colors.white, fontSize: 12),
  ),
  backgroundColor: statusColor(status),
  visualDensity: VisualDensity.compact,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String message, {
  String actionLabel = 'Confirm',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for the mandatory reason a record is being deleted. Returns the trimmed
/// reason, or null if cancelled. The DELETE button stays disabled until some
/// text is entered, so a record can never be deleted without a reason.
Future<String?> deleteReasonDialog(
  BuildContext context, {
  String title = 'Delete transaction',
  String label = 'Reason for deleting',
}) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Required',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('DELETE'),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return reason;
}

Future<void> showMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ),
  );
}

/// Audit entries recorded against one transaction or reward, newest first.
class AuditTrailList extends StatefulWidget {
  const AuditTrailList({super.key, required this.refId});

  final String refId;

  @override
  State<AuditTrailList> createState() => _AuditTrailListState();
}

class _AuditTrailListState extends State<AuditTrailList> {
  List<AuditLog>? _logs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await AppScope.of(context).audit.logsFor(widget.refId);
    if (mounted) setState(() => _logs = logs);
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    if (logs == null) return const Center(child: CircularProgressIndicator());
    if (logs.isEmpty) {
      return const EmptyState(message: 'No audit entries for this item.');
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: logs.length,
      itemBuilder: (ctx, i) {
        final l = logs[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.fact_check, size: 20),
          title: Text(l.action),
          subtitle: Text(
            [
              '${l.userName} · ${l.createdLocal}',
              if (l.oldValue != null) 'From: ${l.oldValue}',
              if (l.newValue != null) 'To: ${l.newValue}',
            ].join('\n'),
          ),
        );
      },
    );
  }
}

Future<void> showAuditTrail(BuildContext context, String refId) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audit trail'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: AuditTrailList(refId: refId),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );

/// Confirmation before cash leaves the box. [label] names the payment, e.g.
/// "Ko Aung · commission".
Future<bool> confirmMarkPaid(
  BuildContext context, {
  required String label,
  required int amount,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm payment'),
      content: Text(
        'Pay ${fmtMMK(amount)} for $label now?\n'
        'The cash box will be ${fmtMMK(amount)} lighter.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Pay now'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Admin-PIN gate for sensitive actions: deleting or correcting a transaction,
/// taking a payment back, overriding a QR-only delivery man, and closing a
/// month. Staff never need a daily code; they call the admin over.
Future<bool> askAdminPin(
  BuildContext context, {
  required String reason,
  String title = 'Admin approval needed',
}) async {
  final controller = TextEditingController();
  final entered = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(reason),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Admin PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
  if (entered == null || !context.mounted) return false;
  final ok = await AppScope.of(context).auth.verifyAdminPin(entered);
  if (!ok && context.mounted) {
    showMessage(context, 'Wrong admin PIN', error: true);
  }
  return ok;
}

Future<bool> askStaffOrAdminPin(
  BuildContext context, {
  required String reason,
  String title = 'Approval needed',
}) async {
  final controller = TextEditingController();
  final entered = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(reason),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Staff or Admin PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
  if (entered == null || !context.mounted) return false;
  final ok = await AppScope.of(context).auth.verifyAnyPin(entered);
  if (!ok && context.mounted) {
    showMessage(context, 'Wrong PIN', error: true);
  }
  return ok;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.teal),
    ),
  );
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: body,
    floatingActionButton: floatingActionButton,
  );
}

/// A shrink-wrapped card grid (never scrolls itself) whose column count follows
/// the width it is given: one column per ~240px, never fewer than 2. The same
/// layout therefore stays usable in a narrow window and on a maximised
/// desktop, where a fixed 2-column grid would stretch cards to phone sizes.
class AutoGrid extends StatelessWidget {
  const AutoGrid({
    super.key,
    required this.children,
    this.childAspectRatio = 1.35,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
  });

  final List<Widget> children;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth ~/ 240;
      return GridView.count(
        crossAxisCount: columns < 2 ? 2 : columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
        children: children,
      );
    },
  );
}
