import 'dart:async';

import 'package:flutter/material.dart';

import '../print/print_spool_watcher.dart';
import 'common.dart';
import 'scan_flow.dart';

/// Windows office screen: shows the print-spool watcher the app runs in the
/// background and turns each printed receipt into a delivery record.
///
/// It replaces the phone's "scan the barcode" step. A detected invoice number
/// feeds the same flow the phone uses — pick delivery man, pick commission
/// (1,000 / 2,000 / 3,000), confirm — and the same delivery card is shown.
///
/// Detection itself belongs to the app (main.dart): every receipt opens the
/// flow wherever the user is, and leaving this screen no longer stops it.
/// This screen lists what was detected and can stop or start the watching.
class PrintMonitorScreen extends StatefulWidget {
  const PrintMonitorScreen({super.key, this.watcher});

  /// Injected in tests; a real spool watcher is created when null.
  final PrintSpoolWatcher? watcher;

  @override
  State<PrintMonitorScreen> createState() => _PrintMonitorScreenState();
}

class _PrintMonitorScreenState extends State<PrintMonitorScreen> {
  late final PrintSpoolWatcher _watcher;
  StreamSubscription<PrintedInvoice>? _subscription;
  final List<PrintedInvoice> _invoices = [];

  @override
  void initState() {
    super.initState();
    // The app owns the watcher and keeps it running across navigation; an
    // injected watcher (tests) is used as-is.
    _watcher = widget.watcher ?? officeSpoolWatcher;
    _subscription = _watcher.invoices.listen(_onInvoice);
    _watcher.start();
    // The folder/error state is only known after the first poll completes.
    _watcher.ready.then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // The watcher is never disposed here: the app owns it and keeps watching
    // after this screen closes (an injected test watcher is the test's).
    _subscription?.cancel();
    super.dispose();
  }

  /// The app opens the flow for each invoice itself (see main.dart), so this
  /// screen only records it for the lists shown here.
  void _onInvoice(PrintedInvoice printed) {
    if (!mounted) return;
    setState(() => _invoices.insert(0, printed));
  }

  void _toggle() {
    setState(() {
      if (_watcher.isRunning) {
        _watcher.stop();
      } else {
        _watcher.start();
      }
    });
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final invoice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter invoice number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'e.g. 001KHL0001234',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (invoice != null && invoice.isNotEmpty && mounted) {
      _openFlow(PrintedInvoice(invoice: invoice));
    }
  }

  void _openFlow(PrintedInvoice printed) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SelectDeliveryManScreen(barcode: printed.invoice, receipt: printed),
      ),
    );
  }

  /// The labelled fields the shop reads off the receipt, for the list rows.
  /// Empty when the job carried none of them.
  String _summary(PrintedInvoice printed) => [
    if (printed.name != null && printed.name!.isNotEmpty) printed.name!,
    if (printed.ageSex != null && printed.ageSex!.isNotEmpty)
      'Age/Sex: ${printed.ageSex}',
    if (printed.refer != null && printed.refer!.isNotEmpty)
      'Refer: ${printed.refer}',
    if (printed.date != null && printed.date!.isNotEmpty)
      'Date: ${printed.date}',
    if (printed.totalAmount != null && printed.totalAmount!.isNotEmpty)
      printed.totalAmount!,
  ].join(' · ');

  Widget _invoiceTile(PrintedInvoice printed) {
    final summary = _summary(printed);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.qr_code),
        title: Text(
          printed.invoice,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: summary.isEmpty
            ? null
            : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        isThreeLine: summary.isNotEmpty,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openFlow(printed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _watcher.isRunning;
    final error = _watcher.lastError;
    final latest = _invoices.isEmpty ? null : _invoices.first;

    return PageScaffold(
      title: 'Print Monitor',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                running ? Icons.print : Icons.print_disabled,
                color: running ? Colors.teal : Colors.grey,
              ),
              title: Text(running ? 'Watching print jobs' : 'Stopped'),
              subtitle: Text('Folder: ${_watcher.directory}'),
              trailing: FilledButton(
                onPressed: _toggle,
                child: Text(running ? 'STOP' : 'START'),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _manualEntry,
            icon: const Icon(Icons.keyboard),
            label: const Text('Enter invoice manually'),
          ),
          if (latest != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.teal.shade300, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.receipt_long, color: Colors.teal),
                        SizedBox(width: 8),
                        Text(
                          'LAST PRINTED INVOICE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        latest.invoice,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                    ...receiptFieldLines(latest),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: () => _openFlow(latest),
                      icon: const Icon(Icons.person_search),
                      label: const Text(
                        'SELECT DELIVERY MAN',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SectionTitle('Detected invoices (${_invoices.length})'),
          if (_invoices.isEmpty)
            const EmptyState(
              message:
                  'Waiting for a print job…\n'
                  'Print a receipt and the invoice number appears here.\n\n'
                  'If nothing shows up, print a test receipt and check the '
                  'folder and permissions above.',
            )
          else
            for (final printed in _invoices) _invoiceTile(printed),
        ],
      ),
    );
  }
}
