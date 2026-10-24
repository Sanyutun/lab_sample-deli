import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/state_views.dart';

/// One delivery in full, with its payment history. Everything here is read from
/// the office server; there is no control that changes an amount or a status.
class CommissionDetailScreen extends StatefulWidget {
  const CommissionDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<CommissionDetailScreen> createState() => _CommissionDetailScreenState();
}

class _CommissionDetailScreenState extends State<CommissionDetailScreen> {
  CommissionDto? _item;
  bool _loading = true;
  bool _stale = false;
  DateTime? _cachedAt;
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
      final result = await AppScope.of(context).repository
          .commission(widget.id);
      if (!mounted) return;
      setState(() {
        _item = result.value;
        _stale = result.stale;
        _cachedAt = result.cachedAt;
        _loading = false;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.deliveryDetails)),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final c = _item!;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_stale) OfflineBanner(cachedAt: _cachedAt),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.barcode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _row(S.deliveryTime, fmtDateTime(c.dateTime)),
                _row(S.commissionLabel, fmtMMK(c.commission)),
                _row(S.paymentStatus, paymentLabel(c.isPaid)),
                if (c.paidAt != null) _row(S.paidOn, fmtDateTime(c.paidAt!)),
                _row(
                  S.officialReceipt,
                  reconciliationLabel(c.reconciliationStatus),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            S.paymentHistory,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 4),
        if (c.payments.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history, color: Colors.grey),
              title: Text(S.noPaymentsYet),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < c.payments.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _paymentTile(c.payments[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          S.officeKeepsRecord,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(PaymentEntryDto p) {
    final negative = p.amount < 0;
    return ListTile(
      dense: true,
      leading: Icon(
        negative ? Icons.remove_circle_outline : Icons.add_circle_outline,
        color: negative ? Colors.deepOrange : Colors.green,
      ),
      title: Text(paymentEntryLabel(p.type)),
      subtitle: Text(p.note.isEmpty ? p.date : '${p.date} • ${p.note}'),
      trailing: Text(
        fmtMMK(p.amount),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: negative ? Colors.deepOrange : Colors.green.shade800,
        ),
      ),
    );
  }
}
