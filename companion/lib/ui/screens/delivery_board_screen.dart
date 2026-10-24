import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/new_delivery_banner.dart';
import '../widgets/state_views.dart';
import '../widgets/stat_card.dart';

/// The delivery man's own delivery board, read-only.
///
/// The board is derived by the office from the same records staff see; this
/// screen only renders it for the signed-in man. There is no delivery-man
/// selector, no scan and no delete — this phone cannot create or change a
/// delivery.
class DeliveryBoardScreen extends StatefulWidget {
  const DeliveryBoardScreen({super.key});

  @override
  State<DeliveryBoardScreen> createState() => _DeliveryBoardScreenState();
}

class _DeliveryBoardScreenState extends State<DeliveryBoardScreen> {
  final ScrollController _scroll = ScrollController();

  DeliveryBoardDto? _board;
  bool _loading = true;
  bool _stale = false;
  DateTime? _cachedAt;
  String? _error;

  double _groupExtent = 0;
  int _currentVisibleIndex = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
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

  /// The office only sends groups that hold a delivery, so this is every group
  /// the man has something in.
  List<BoardGroupDto> get _visibleGroups => _board?.groups ?? const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppScope.of(context).repository.deliveryBoard();
      if (!mounted) return;
      // A pull-to-refresh is a real read of the board: let the watch announce
      // anything that appeared since the last one, instead of staying silent
      // until its next poll.
      unawaited(AppScope.of(context).watch.observe(result.value));
      setState(() {
        _board = result.value;
        _stale = result.stale;
        _cachedAt = result.cachedAt;
        _loading = false;
        _currentVisibleIndex = 0;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
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
    final index = _visibleGroups.indexWhere(
      (g) => g.groupNumber == groupNumber,
    );
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.groupHasNoDeliveries(groupNumber))),
      );
      return;
    }
    _goToVisibleIndex(index);
  }

  void _openDetail(BoardSlotDto slot) {
    if (slot.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.emptyPositionNote)));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SlotDetailSheet(slot: slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.boardTitle),
        actions: [
          IconButton(
            tooltip: S.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final board = _board!;
    return Column(
      children: [
        // The alert belongs where the man is looking: on the board itself, not
        // only on the shell behind it.
        _banner(),
        if (_stale) OfflineBanner(cachedAt: _cachedAt),
        _buildSummary(board),
        _buildControls(),
        Expanded(child: _buildBoard()),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Text(
            S.boardFootnote,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _banner() {
    final watch = AppScope.of(context).watch;
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) => NewDeliveryBanner(
        deliveries: watch.pending,
        onViewBoard: watch.clear,
        onDismiss: watch.clear,
      ),
    );
  }

  Widget _buildSummary(DeliveryBoardDto board) {
    final s = board.summary;
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          _summaryCard(
            S.successfulOverPositions,
            value: '${s.successfulDeliveries} / ${s.totalSlots}',
            icon: Icons.local_shipping,
          ),
          _summaryCard(
            S.commissionEarned,
            amount: s.commissionEarned,
            color: Colors.teal,
            icon: Icons.savings,
          ),
          _summaryCard(
            S.commissionPaid,
            amount: s.commissionPaid,
            color: Colors.green,
            icon: Icons.payments,
          ),
          _summaryCard(
            S.unpaidCommission,
            amount: s.unpaidCommission,
            color: s.unpaidCommission > 0 ? Colors.red : Colors.grey,
            icon: Icons.pending_actions,
          ),
          _summaryCard(
            S.rewardsEarned,
            amount: s.rewardsEarned,
            color: Colors.amber.shade800,
            icon: Icons.emoji_events,
          ),
          _summaryCard(
            S.rewardsPaid,
            amount: s.rewardsPaid,
            color: Colors.green,
            icon: Icons.redeem,
          ),
          _summaryCard(
            S.unpaidBalance,
            amount: s.unpaidBalance,
            color: s.unpaidBalance > 0
                ? Colors.red.shade700
                : Colors.green.shade700,
            icon: Icons.account_balance_wallet,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String label, {
    String? value,
    int? amount,
    Color? color,
    IconData? icon,
  }) => SizedBox(
    width: 158,
    child: StatCard(
      label: label,
      value: value,
      amount: amount,
      color: color,
      icon: icon,
    ),
  );

  Widget _buildControls() {
    final groups = _visibleGroups;
    final total = groups.length;
    final current = total == 0 ? 0 : _currentVisibleIndex + 1;
    final currentGroup = total == 0
        ? 0
        : groups[_currentVisibleIndex.clamp(0, total - 1)].groupNumber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: S.firstGroup,
                onPressed: total == 0 ? null : () => _goToVisibleIndex(0),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: S.previousGroup,
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(_currentVisibleIndex - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  S.groupCounter(currentGroup, current, total),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: S.nextGroup,
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(_currentVisibleIndex + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: S.lastGroup,
                onPressed: total == 0
                    ? null
                    : () => _goToVisibleIndex(total - 1),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: S.jumpToGroup,
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
        ],
      ),
    );
  }

  Widget _buildBoard() {
    final groups = _visibleGroups;
    if (groups.isEmpty) {
      return const EmptyView(message: S.noDeliveriesYet, icon: Icons.grid_view);
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const hPad = 12.0;
        const gap = 6.0;
        const rowGap = 8.0;
        const headerH = 42.0;
        const vPad = 6.0;
        final cardWidth = (constraints.maxWidth - hPad * 2 - gap * 4) / 5;
        final cardHeight = cardWidth * 1.12;
        _groupExtent = headerH + rowGap * 2 + cardHeight * 2 + vPad * 2;

        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            controller: _scroll,
            itemExtent: _groupExtent,
            itemCount: groups.length,
            itemBuilder: (ctx, i) => _GroupView(
              group: groups[i],
              hPad: hPad,
              gap: gap,
              rowGap: rowGap,
              headerHeight: headerH,
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
    required this.cardHeight,
    required this.onCardTap,
  });

  final BoardGroupDto group;
  final double hPad;
  final double gap;
  final double rowGap;
  final double headerHeight;
  final double cardHeight;
  final void Function(BoardSlotDto slot) onCardTap;

  @override
  Widget build(BuildContext context) {
    final slots = group.slots;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: headerHeight, child: _header(context)),
          SizedBox(height: rowGap),
          _row(context, slots.sublist(0, 5)),
          SizedBox(height: rowGap),
          _row(context, slots.sublist(5, 10)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<BoardSlotDto> rowSlots) => SizedBox(
    height: cardHeight,
    child: Row(
      children: [
        for (var i = 0; i < rowSlots.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: _SlotCard(
              slot: rowSlots[i],
              onTap: () => onCardTap(rowSlots[i]),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        children: [
          Text(
            S.groupHeading(group.groupNumber),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.deliveriesRange(group.startNumber, group.endNumber),
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
        S.groupSummary(group.successfulCount, fmtMMK(group.commissionTotal)),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Colors.black54),
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  /// One chip per milestone reward earned inside a group. Rules are office
  /// configured, so the amount is shown and there is no fixed tier colour.
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

/// One slot, styled exactly like the office board card but reading the DTO.
class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, this.onTap});

  final BoardSlotDto slot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = _style();
    final borderColor = slot.milestoneAmount != null
        ? Colors.amber.shade700
        : border;
    final borderWidth = slot.milestoneAmount != null ? 2.0 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        slot.number.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: fg,
                        ),
                      ),
                    ),
                    FittedBox(fit: BoxFit.scaleDown, child: _statusBadge(fg)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _amountLabel(),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (slot.milestoneAmount != null)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Icon(
                    Icons.emoji_events,
                    size: 12,
                    color: Colors.amber.shade700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(Color fg) {
    if (slot.isEmpty) return const SizedBox.shrink();
    final icon = slot.paid ? Icons.check_circle : Icons.hourglass_bottom;
    final label = slot.state == 'reversed'
        ? S.badgeReversed
        : (slot.paid ? S.badgePaid : S.badgeUnpaid);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 2),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: fg,
          ),
        ),
      ],
    );
  }

  String _amountLabel() => switch (slot.state) {
    'successful' || 'pending' => NumberFormat('#,###').format(slot.commission),
    _ => '',
  };

  (Color bg, Color border, Color fg) _style() {
    if (slot.isEmpty) {
      return (Colors.grey.shade100, Colors.grey.shade300, Colors.grey.shade500);
    }
    if (slot.state == 'reversed') {
      return (Colors.red.shade50, Colors.red.shade200, Colors.red.shade400);
    }
    if (slot.paid) {
      return (
        Colors.green.shade50,
        Colors.green.shade400,
        Colors.green.shade800,
      );
    }
    return (Colors.amber.shade50, Colors.amber.shade600, Colors.amber.shade900);
  }
}

/// Read-only detail for one delivery. There is no delete: only the office can
/// reverse a transaction.
class _SlotDetailSheet extends StatelessWidget {
  const _SlotDetailSheet({required this.slot});

  final BoardSlotDto slot;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
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
                    '${S.deliveryNumber} ${slot.number} · ${_stateLabel()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row(S.receiptBarcode, slot.barcode ?? S.dash),
            _row(S.commissionLabel, fmtMMK(slot.commission)),
            _row(
              S.recordedAt,
              slot.recordedAt == null ? S.dash : fmtDateTime(slot.recordedAt!),
            ),
            _row(S.paymentStatus, paymentLabel(slot.paid)),
            _row(
              S.officialReceipt,
              slot.reconciliationStatus == null
                  ? S.notSet
                  : reconciliationLabel(slot.reconciliationStatus!),
            ),
            const SizedBox(height: 8),
            Text(
              S.officeKeepsRecord,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  IconData _stateIcon() => switch (slot.state) {
    'successful' => Icons.check_circle,
    'pending' => Icons.hourglass_bottom,
    'reversed' => Icons.delete,
    _ => Icons.horizontal_rule,
  };

  Color _stateColor() => switch (slot.state) {
    'successful' => Colors.green,
    'pending' => Colors.amber.shade800,
    'reversed' => Colors.red.shade400,
    _ => Colors.grey,
  };

  String _stateLabel() => switch (slot.state) {
    'successful' => S.stateSuccessful,
    'pending' => S.statePending,
    'reversed' => S.stateReversed,
    _ => S.stateEmpty,
  };

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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
