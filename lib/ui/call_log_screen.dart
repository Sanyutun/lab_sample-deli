import 'package:flutter/material.dart';

import '../calls/incoming_calls.dart';
import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/services/call_log_service.dart';
import 'common.dart';

/// Every incoming call from a delivery man, newest first — the evidence that
/// a man who sent a patient in called the lab to say so. Opened from the
/// dashboard, or filtered to one man from his card in Delivery Men.
class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key, this.deliveryManId});

  /// When set, only this man's calls are listed.
  final String? deliveryManId;

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  List<DeliveryManCall> _calls = [];
  Map<String, List<CommissionRecord>> _linked = {};
  Map<String, PrintedReceipt> _receipts = {};
  Map<String, String> _names = {};
  String _filterName = '';
  bool _loading = true;
  bool _needsPermission = false;
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
      final men = await services.deliveryMen.all();
      final calls = await services.callLog.recent(forMan: widget.deliveryManId);
      final records = await services.commissions.all(
        deliveryManId: widget.deliveryManId,
      );
      final receipts = receiptDetailsByBarcode(
        await services.printedReceipts.byBarcode(),
        await services.receipts.officialReceiptsByBarcode(),
      );
      final granted = await IncomingCalls.hasPermission();
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _linked = receiptsByCall(calls, records);
        _receipts = receipts;
        _names = {for (final m in men) m.id: m.name};
        _filterName = men
            .where((m) => m.id == widget.deliveryManId)
            .map((m) => m.name)
            .join();
        _loading = false;
        _needsPermission = !granted;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _allow() async {
    await IncomingCalls.requestPermission();
    await _load();
  }

  void _showReceipts(DeliveryManCall call, List<CommissionRecord> linked) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_names[call.deliveryManId] ?? 'Delivery man'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Call: ${fmtDate(call.receivedAt)} · ${call.phone}'),
              const SizedBox(height: 4),
              Text(
                linked.isEmpty
                    ? 'No receipts were recorded for this man before his '
                          'next call that day.'
                    : '${linked.length} receipt(s) recorded before his next '
                          'call that day:',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              if (linked.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: linked.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = linked[i];
                      final receipt = _receipts[r.barcode];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.barcode),
                        subtitle: Text(
                          [
                            if (receipt != null && receipt.patient.isNotEmpty)
                              receipt.patient,
                            fmtDate(r.dateTime),
                            fmtMMK(r.commission),
                            r.isActive ? 'active' : 'reversed',
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: _filterName.isEmpty ? 'Call Log' : 'Call Log · $_filterName',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? EmptyState(message: _error!, onRetry: _load)
          : Column(
              children: [
                if (_needsPermission)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    color: Colors.orange.shade50,
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber,
                        color: Colors.orange,
                      ),
                      title: const Text('Phone permission is off'),
                      subtitle: const Text(
                        'Android cannot tell which number is calling, '
                        'so no calls are logged.',
                      ),
                      trailing: FilledButton(
                        onPressed: _allow,
                        child: const Text('ALLOW'),
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'Tap a call to see the receipts recorded for that man '
                    'before his next call that day.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: _calls.isEmpty
                      ? const EmptyState(
                          message: 'No calls from delivery men yet.',
                        )
                      : ListView.builder(
                          itemCount: _calls.length,
                          itemBuilder: (ctx, i) {
                            final c = _calls[i];
                            final linked = _linked[c.id] ?? const [];
                            final count = linked.length;
                            return ListTile(
                              onTap: () => _showReceipts(c, linked),
                              leading: Icon(
                                c.answered
                                    ? Icons.call_received
                                    : Icons.call_missed,
                                color: c.answered
                                    ? Colors.teal
                                    : Colors.deepOrange,
                              ),
                              title: Text(
                                _names[c.deliveryManId] ??
                                    'Unknown delivery man',
                              ),
                              subtitle: Text(
                                '${fmtDate(c.receivedAt)} · ${c.phone}\n'
                                '$count receipt${count == 1 ? '' : 's'} '
                                'after this call',
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                c.answered ? 'answered' : 'missed',
                                style: TextStyle(
                                  color: c.answered
                                      ? Colors.teal
                                      : Colors.deepOrange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
