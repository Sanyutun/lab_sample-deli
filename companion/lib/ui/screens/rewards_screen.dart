import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/state_views.dart';

/// Milestone rewards, kept separate from commission. Rewards are decided and
/// created by the office from its own rules; this app only displays them.
class RewardsTab extends StatefulWidget {
  const RewardsTab({super.key});

  @override
  State<RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<RewardsTab> {
  List<RewardDto>? _items;
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
      final result = await AppScope.of(context).repository.rewards();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final items = _items!;

    return Column(
      children: [
        if (_stale) OfflineBanner(cachedAt: _cachedAt),
        Expanded(
          child: items.isEmpty
              ? const EmptyView(
                  message: S.noRewardsYet,
                  icon: Icons.emoji_events,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      Card(
                        color: Colors.amber.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            S.rewardsNote,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final r in items) _card(r),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _card(RewardDto r) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: r.isPaid
              ? Colors.green.shade100
              : Colors.amber.shade100,
          child: Icon(
            r.isPaid ? Icons.check : Icons.emoji_events,
            color: r.isPaid ? Colors.green.shade800 : Colors.amber.shade900,
          ),
        ),
        title: Text(
          rewardRuleLabel(r.everyN, r.rewardAmount),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.reachedAt(r.milestoneCount)),
            Text(
              r.isPaid && r.paidAt != null
                  ? S.paidOnDate(fmtDate(r.paidAt!))
                  : S.addedOnDate(fmtDate(r.createdAt)),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtMMK(r.rewardAmount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              paymentLabel(r.isPaid),
              style: TextStyle(
                fontSize: 12,
                color: r.isPaid ? Colors.green : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
