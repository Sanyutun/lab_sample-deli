// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/delivery_board.dart';
import '../domain/exceptions.dart';
import 'common.dart';
import 'delivery_card.dart';
import 'scan_flow.dart';

/// Card-based delivery progress board for a single delivery man.
///
/// A delivery man holds 200 groups x 10 positions = 2,000 visual slots.
/// Slots only *represent* positions; the underlying transactions are the
/// single source of truth and are never created from this screen.
class SuccessfulDeliveryScreen extends StatefulWidget {
  const SuccessfulDeliveryScreen({super.key});

  @override
  State<SuccessfulDeliveryScreen> createState() =>
      _SuccessfulDeliveryScreenState();
}

class _SuccessfulDeliveryScreenState extends State<SuccessfulDeliveryScreen> {
  final ScrollController _scroll = ScrollController();

  List<DeliveryMan> _men = [];
  Map<String, String> _staffNames = {};
  Map<String, PrintedReceipt> _receipts = {};
  DeliveryMan? _selected;
  DeliveryBoard? _board;

  bool _loadingMen = true;
  bool _loadingBoard = false;
  bool _hideEmptyGroups = false;
  String? _error;

  double _groupExtent = 0;
  int _currentVisibleIndex = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMen();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_groupExtent <= 0 || _visibleGroups.isEmpty) return;
    final idx = (_scroll.offset / _groupExtent).floor().clamp(
      0,
      _visibleGroups.length - 1,
    );
    if (idx != _currentVisibleIndex) {
      setState(() => _currentVisibleIndex = idx);
    }
  }

  List<DeliveryGroup> get _visibleGroups {
    final board = _board;
    if (board == null) return const [];
    if (!_hideEmptyGroups) return board.groups;
    return board.groups.where((g) => g.slots.any((s) => !s.isEmpty)).toList();
  }

  Future<void> _loadMen() async {
    final services = AppScope.of(context);
    setState(() {
      _loadingMen = true;
      _error = null;
    });
    try {
      final men = await services.deliveryMen.all();
      final users = await services.users.all();
      if (!mounted) return;
      final active = men.where((m) => m.active).toList();
      setState(() {
        _men = men;
        _staffNames = {for (final u in users) u.id: u.name};
        _loadingMen = false;
        _selected = active.isNotEmpty
            ? active.first
            : (men.isNotEmpty ? men.first : null);
      });
      if (_selected != null) await _loadBoard();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMen = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadBoard() async {
    final man = _selected;
    if (man == null) {
      setState(() {
        _board = null;
        _loadingBoard = false;
      });
      return;
    }
    setState(() {
      _loadingBoard = true;
      _error = null;
    });
    final services = AppScope.of(context);
    try {
      final records = await services.commissions.all(deliveryManId: man.id);
      final receipts = receiptDetailsByBarcode(
        await services.printedReceipts.byBarcode(),
        await services.receipts.officialReceiptsByBarcode(),
      );
      final rewards = await services.milestones.rewards(deliveryManId: man.id);
      final (_, results) = await services.reconciliation.latest();
      final recon = <String, ReconciliationStatus>{};
      for (final r in results) {
        recon.putIfAbsent(r.barcode, () => r.status);
      }
      final board = DeliveryBoard.from(
        records: records,
        rewards: rewards,
        reconciliationByBarcode: recon,
      );
      if (!mounted) return;
      setState(() {
        _board = board;
        _receipts = receipts;
        _loadingBoard = false;
        _currentVisibleIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBoard = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickDeliveryMan() async {
    final query = ValueNotifier<String>('');
    final picked = await showModalBottomSheet<DeliveryMan>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name, phone or ID',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => query.value = v,
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, q, _) {
                    final needle = q.toLowerCase();
                    final filtered = _men
                        .where(
                          (m) =>
                              needle.isEmpty ||
                              m.name.toLowerCase().contains(needle) ||
                              m.phone.toLowerCase().contains(needle) ||
                              m.id.toLowerCase().contains(needle),
                        )
                        .toList();
                    if (filtered.isEmpty) {
                      return const EmptyState(
                        message: 'No matching delivery men.',
                      );
                    }
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final man = filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(man.name.isEmpty ? '?' : man.name[0]),
                          ),
                          title: Text(man.name),
                          subtitle: Text(
                            '${man.id}${man.phone.isNotEmpty ? ' · ${man.phone}' : ''}',
                          ),
                          trailing: man.active
                              ? (man.id == _selected?.id
                                    ? const Icon(Icons.check)
                                    : null)
                              : const Chip(
                                  label: Text(
                                    'INACTIVE',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                          onTap: () => Navigator.pop(ctx, man),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _selected = picked);
      await _loadBoard();
    }
  }

  void _goToVisibleIndex(int index) {
    if (!_scroll.hasClients || _groupExtent <= 0) return;
    final total = _visibleGroups.length;
    if (total == 0) return;
    final clamped = index.clamp(0, total - 1);
    _scroll.animateTo(
      clamped * _groupExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    setState(() => _currentVisibleIndex = clamped);
  }

  void _jumpToGroup(int groupNumber) {
    final groups = _visibleGroups;
    final index = groups.indexWhere((g) => g.groupNumber == groupNumber);
    if (index < 0) {
      showMessage(
        context,
        'Group $groupNumber is hidden by the current filter.',
        error: true,
      );
      return;
    }
    _goToVisibleIndex(index);
  }

  Future<void> _openScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanReceiptScreen()),
    );
    if (mounted) await _loadBoard();
  }

  Future<void> _openDetail(DeliverySlot slot) async {
    if (slot.isEmpty) {
      showMessage(
        context,
        'Empty slot. New deliveries are created only through the barcode scan workflow.',
      );
      return;
    }
    final record = slot.record!;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SlotDetailSheet(
        record: record,
        printed: _receipts[record.barcode],
        slotNumber: slot.number,
        deliveryManName: _selected?.name ?? record.deliveryManId,
        state: slot.state,
        staffName: _staffNames[record.staffUserId] ?? record.staffUserId,
        reconciliationStatus: slot.reconciliationStatus,
        onDelete: () => _delete(record),
        onTogglePayment: () => _togglePayment(record),
      ),
    );
    if (changed == true && mounted) await _loadBoard();
  }

  /// Marks the delivery paid (cash leaves the box) or takes the payment back
  /// (admin PIN: the money returns to the box).
  Future<bool> _togglePayment(CommissionRecord record) async {
    final name = _selected?.name ?? record.deliveryManId;
    if (!record.isPaid) {
      if (!await confirmMarkPaid(
        context,
        label: '$name · commission',
        amount: record.commission,
      )) {
        return false;
      }
    } else if (!await askStaffOrAdminPin(
      context,
      reason:
          'Take back the ${fmtMMK(record.commission)} commission paid to $name?',
    )) {
      return false;
    }
    if (!mounted) return false;
    try {
      final services = AppScope.of(context);
      await services.delivery.togglePaymentStatus(
        recordId: record.id,
        staffUserId: services.auth.requireUser().id,
      );
      showMessage(
        context,
        record.isPaid
            ? 'Payment taken back (+${fmtMMK(record.commission)})'
            : 'Commission paid (-${fmtMMK(record.commission)})',
      );
      return true;
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
      return false;
    }
  }

  Future<bool> _delete(CommissionRecord record) async {
    final reason = await deleteReasonDialog(context);
    if (reason == null) return false;
    if (!await askStaffOrAdminPin(
      context,
      reason: 'Delete transaction ${record.barcode}?',
    )) {
      return false;
    }
    try {
      final services = AppScope.of(context);
      await services.delivery.reverse(
        recordId: record.id,
        reason: reason,
        byUserId: services.auth.requireUser().id,
      );
      showMessage(
        context,
        'Transaction deleted. Original record kept for audit.',
      );
      if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
      return true;
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Successful Delivery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _selected == null ? null : _loadBoard,
          ),
        ],
      ),
      floatingActionButton: _selected == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
            ),
      body: _loadingMen
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? EmptyState(message: _error!, onRetry: _loadMen)
          : _men.isEmpty
          ? const EmptyState(
              message: 'No delivery men registered yet.\nAsk an admin to add one first.',
            )
          : Column(
              children: [
                _buildSummary(context),
                _buildSelector(context),
                _buildControls(context),
                Expanded(child: _buildBoard(context)),
              ],
            ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final board = _board;
    if (board == null || _loadingBoard) {
      return const SizedBox(
        height: 88,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = board.summary;
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _summaryCard(
            context,
            'Successful / slots',
            '${s.successfulDeliveries} / ${s.totalSlots}',
            color: Colors.teal,
          ),
          _summaryCard(
            context,
            'Commission earned',
            fmtMMK(s.commissionEarned),
          ),
          _summaryCard(context, 'Commission paid', fmtMMK(s.commissionPaid)),
          _summaryCard(
            context,
            'Unpaid commission',
            fmtMMK(s.unpaidCommission),
            color: s.unpaidCommission > 0 ? Colors.orange.shade800 : null,
          ),
          _summaryCard(
            context,
            'Rewards earned',
            fmtMMK(s.rewardsEarned),
            color: Colors.amber.shade800,
          ),
          _summaryCard(context, 'Rewards paid', fmtMMK(s.rewardsPaid)),
          _summaryCard(
            context,
            'Unpaid balance',
            fmtMMK(s.unpaidBalance),
            color: s.unpaidBalance > 0
                ? Colors.red.shade700
                : Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return SizedBox(
      width: 142,
      height: 80,
      child: statCard(context, label, value, color: color),
    );
  }

  Widget _buildSelector(BuildContext context) {
    final man = _selected;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(man == null || man.name.isEmpty ? '?' : man.name[0]),
        ),
        title: Text(
          man?.name ?? 'Select delivery man',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          man == null
              ? 'Tap to choose'
              : 'ID ${man.id}${man.active ? '' : ' · INACTIVE'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: _pickDeliveryMan,
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final groups = _visibleGroups;
    final total = groups.length;
    final current = total == 0 ? 0 : _currentVisibleIndex + 1;
    final currentGroup = total == 0
        ? 0
        : groups[_currentVisibleIndex.clamp(0, total - 1)].groupNumber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'First group',
                onPressed: total == 0 ? null : () => _goToVisibleIndex(0),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Previous group',
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(_currentVisibleIndex - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Group $currentGroup  ·  $current / $total',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Next group',
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(_currentVisibleIndex + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Last group',
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(total - 1),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Jump to group #',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null) _jumpToGroup(n);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Only non-empty'),
                selected: _hideEmptyGroups,
                onSelected: (v) {
                  setState(() {
                    _hideEmptyGroups = v;
                    _currentVisibleIndex = 0;
                  });
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final board = _board;
    if (board == null || _loadingBoard) {
      _groupExtent = 0;
      return const Center(child: CircularProgressIndicator());
    }
    final groups = _visibleGroups;
    if (groups.isEmpty) {
      _groupExtent = 0;
      return const EmptyState(message: 'No groups to display.');
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const gap = 6.0;
        const rowGap = 6.0;
        const headerH = 42.0;
        const vPad = 4.0;
        // Compact fixed-size cards, centred. Stretching them to fill the width
        // made a 10-slot group taller than a typical window; on a narrow window
        // they shrink to fit instead of overflowing.
        const cardW = 84.0;
        const hPad = 12.0;
        final available = constraints.maxWidth - hPad * 2 - gap * 4;
        final cardWidth = (available / 5).clamp(40.0, cardW);
        final cardHeight = cardWidth * 0.74;
        final extent = headerH + rowGap * 2 + cardHeight * 2 + vPad * 2;
        _groupExtent = extent;
        final hInset = ((constraints.maxWidth - (cardWidth * 5 + gap * 4)) / 2)
            .clamp(8.0, double.infinity);

        return RefreshIndicator(
          onRefresh: _loadBoard,
          child: ListView.builder(
            controller: _scroll,
            itemExtent: extent,
            itemCount: groups.length,
            itemBuilder: (ctx, i) => _GroupView(
              group: groups[i],
              hPad: hInset,
              gap: gap,
              rowGap: rowGap,
              headerHeight: headerH,
              cardWidth: cardWidth,
              cardHeight: cardHeight,
              onCardTap: _openDetail,
            ),
          ),
        );
      },
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.hPad,
    required this.gap,
    required this.rowGap,
    required this.headerHeight,
    required this.cardWidth,
    required this.cardHeight,
    required this.onCardTap,
  });

  final DeliveryGroup group;
  final double hPad;
  final double gap;
  final double rowGap;
  final double headerHeight;
  final double cardWidth;
  final double cardHeight;
  final void Function(DeliverySlot slot) onCardTap;

  @override
  Widget build(BuildContext context) {
    final slots = group.slots;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: headerHeight, child: _buildHeader(context)),
          SizedBox(height: rowGap),
          _buildRow(context, slots.sublist(0, 5)),
          SizedBox(height: rowGap),
          _buildRow(context, slots.sublist(5, 10)),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<DeliverySlot> rowSlots) {
    return SizedBox(
      height: cardHeight,
      child: Row(
        children: [
          for (var i = 0; i < rowSlots.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            SizedBox(
              width: cardWidth,
              child: DeliverySlotCard(
                slot: rowSlots[i],
                onTap: () => onCardTap(rowSlots[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              'Group ${group.groupNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Deliveries ${group.startNumber}–${group.endNumber}',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final amount in group.milestoneAmounts) ...[
              const SizedBox(width: 4),
              _milestoneChip('+${NumberFormat('#,###').format(amount)}'),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${group.successfulCount}/10 successful · ${fmtMMK(group.commissionTotal)}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colors.black54),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// One chip per milestone reward earned inside a group. Every rule is
  /// admin-editable, so the amount is shown and there is no fixed tier colour.
  Widget _milestoneChip(String text) {
    final color = Colors.amber.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotDetailSheet extends StatelessWidget {
  const _SlotDetailSheet({
    required this.record,
    required this.printed,
    required this.slotNumber,
    required this.deliveryManName,
    required this.state,
    required this.staffName,
    required this.reconciliationStatus,
    required this.onDelete,
    required this.onTogglePayment,
  });

  final CommissionRecord record;

  /// What the receipt printed, when the print job was detected.
  final PrintedReceipt? printed;
  final int slotNumber;
  final String deliveryManName;
  final DeliverySlotState state;
  final String staffName;
  final ReconciliationStatus? reconciliationStatus;
  final Future<bool> Function() onDelete;
  final Future<bool> Function() onTogglePayment;

  @override
  Widget build(BuildContext context) {
    final reversed = record.status == RecordStatus.reversed;
    Future<void> togglePayment() async {
      final done = await onTogglePayment();
      if (done && context.mounted) Navigator.pop(context, true);
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(_stateIcon(), color: _stateColor()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Delivery #$slotNumber · ${_stateLabel()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _row('Receipt barcode', record.barcode),
              if (printed?.patient.isNotEmpty ?? false)
                _row('Patient', printed!.patient),
              if (printed?.ageSex.isNotEmpty ?? false)
                _row('Age/Sex', printed!.ageSex),
              if (printed?.refer.isNotEmpty ?? false)
                _row('Refer', printed!.refer),
              if (printed?.receiptDate.isNotEmpty ?? false)
                _row('Receipt date', printed!.receiptDate),
              if (printed?.totalAmount.isNotEmpty ?? false)
                _row('Receipt total', printed!.totalAmount),
              _row('Delivery man', deliveryManName),
              _row('Commission', fmtMMK(record.commission)),
              _row('Recorded at', fmtDate(record.dateTime)),
              _row('Recorded by', staffName),
              _row('Payment status', record.paymentStatus.name.toUpperCase()),
              _row('Reconciliation', _reconLabel()),
              if (reversed) ...[
                const Divider(),
                _row(
                  'Deleted at',
                  record.reversedAt == null ? '-' : fmtDate(record.reversedAt!),
                ),
                _row('Reason', record.reversalReason ?? '-'),
              ],
              const Divider(),
              const Text(
                'Audit trail',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 180, child: AuditTrailList(refId: record.id)),
              const SizedBox(height: 12),
              if (!reversed) ...[
                if (record.isPaid)
                  OutlinedButton.icon(
                    onPressed: togglePayment,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Take payment back'),
                  )
                else
                  FilledButton.icon(
                    onPressed: togglePayment,
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Mark as paid'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Deleting keeps the original record for audit; a reason is required.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: () async {
                    final done = await onDelete();
                    if (done && context.mounted) Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete transaction'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _stateIcon() => switch (state) {
    DeliverySlotState.successful => Icons.check_circle,
    DeliverySlotState.pending => Icons.hourglass_bottom,
    DeliverySlotState.reversed => Icons.delete,
    DeliverySlotState.empty => Icons.horizontal_rule,
  };

  Color _stateColor() => switch (state) {
    DeliverySlotState.successful => Colors.green,
    DeliverySlotState.pending => Colors.amber.shade800,
    DeliverySlotState.reversed => Colors.red.shade400,
    DeliverySlotState.empty => Colors.grey,
  };

  String _stateLabel() => switch (state) {
    DeliverySlotState.successful => 'SUCCESSFUL',
    DeliverySlotState.pending => 'PENDING VERIFICATION',
    DeliverySlotState.reversed => 'DELETED',
    DeliverySlotState.empty => 'EMPTY',
  };

  String _reconLabel() {
    if (reconciliationStatus == null) return 'Not reconciled';
    return switch (reconciliationStatus!) {
      ReconciliationStatus.match => 'MATCH (verified)',
      ReconciliationStatus.mismatch => 'MISMATCH',
      ReconciliationStatus.notFound => 'NOT FOUND',
      ReconciliationStatus.duplicateStaff => 'DUPLICATE (staff)',
      ReconciliationStatus.duplicateOfficial => 'DUPLICATE (official)',
      ReconciliationStatus.unclaimed => 'UNCLAIMED',
    };
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
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
