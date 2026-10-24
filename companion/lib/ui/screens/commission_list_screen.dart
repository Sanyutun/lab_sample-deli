import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/state_views.dart';
import 'commission_detail_screen.dart';

/// Read-only list of this delivery man's deliveries, with date and payment
/// filters. No editing is possible from this screen.
class CommissionListTab extends StatefulWidget {
  const CommissionListTab({super.key});

  @override
  State<CommissionListTab> createState() => _CommissionListTabState();
}

class _CommissionListTabState extends State<CommissionListTab> {
  List<CommissionDto>? _items;
  bool _loading = true;
  bool _stale = false;
  DateTime? _cachedAt;
  String? _error;

  String _status = 'all';
  DateTimeRange? _range;

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
      final result = await AppScope.of(context).repository.commissions(
        from: _range == null ? null : isoDate(_range!.start),
        to: _range == null ? null : isoDate(_range!.end),
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _items = result.value;
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

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (range == null) return;
    setState(() => _range = range);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filterBar(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: S.paymentStatus,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text(S.filterAll)),
                DropdownMenuItem(value: 'unpaid', child: Text(S.filterUnpaid)),
                DropdownMenuItem(value: 'paid', child: Text(S.filterPaid)),
              ],
              onChanged: (value) {
                setState(() => _status = value ?? 'all');
                _load();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                _range == null
                    ? S.anyDate
                    : '${isoDate(_range!.start)} → ${isoDate(_range!.end)}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: _pickRange,
            ),
          ),
          if (_range != null)
            IconButton(
              tooltip: S.clearDateFilter,
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() => _range = null);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final items = _items!;
    return Column(
      children: [
        if (_stale) OfflineBanner(cachedAt: _cachedAt),
        Expanded(
          child: items.isEmpty
              ? const EmptyView(
                  message: S.noDeliveriesMatch,
                  icon: Icons.receipt_long,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => _card(items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _card(CommissionDto c) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.isPaid
              ? Colors.green.shade100
              : Colors.orange.shade100,
          child: Icon(
            c.isPaid ? Icons.check : Icons.schedule,
            color: c.isPaid ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
        title: Text(
          c.barcode,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmtDateTime(c.dateTime)),
            Text(
              reconciliationLabel(c.reconciliationStatus),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtMMK(c.commission),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              c.isPaid ? S.badgePaid : S.badgeUnpaid,
              style: TextStyle(
                fontSize: 12,
                color: c.isPaid ? Colors.green : Colors.orange.shade800,
              ),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CommissionDetailScreen(id: c.id)),
        ),
      ),
    );
  }
}
