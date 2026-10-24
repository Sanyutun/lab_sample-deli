import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/strings.dart';
import '../widgets/new_delivery_banner.dart';
import '../widgets/state_views.dart';
import '../widgets/stat_card.dart';
import 'commission_list_screen.dart';
import 'delivery_board_screen.dart';
import 'location_screen.dart';
import 'profile_screen.dart';
import 'qr_screen.dart';
import 'rewards_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// How often the board is re-read so a newly recorded delivery can be
  /// announced. Twenty seconds is often enough to feel immediate without
  /// hammering the office server.
  static const Duration _checkEvery = Duration(seconds: 20);

  int _index = 0;
  Timer? _watchTimer;
  late final AppLifecycleListener _lifecycle;

  static const _titles = [
    S.titleDashboard,
    S.titleCommission,
    S.titleRewards,
    S.titleLocation,
    S.titleProfile,
  ];

  @override
  void initState() {
    super.initState();
    final watch = AppScope.of(context).watch;
    watch.addListener(_onWatch);
    // The first read only records what already exists; later reads announce
    // what is new.
    unawaited(watch.check());
    _watchTimer = Timer.periodic(_checkEvery, (_) => unawaited(watch.check()));
    // A delivery is usually recorded while the phone is in a pocket. Windows
    // and Android pause timers while the app is backgrounded, so check again
    // the moment it comes back.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(watch.check()));
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _lifecycle.dispose();
    AppScope.of(context).watch.removeListener(_onWatch);
    super.dispose();
  }

  void _onWatch() {
    if (mounted) setState(() {});
  }

  void _openBoard() {
    AppScope.of(context).watch.clear();
    setState(() => _index = 0);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeliveryBoardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watch = AppScope.of(context).watch;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: S.myQrTitle,
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QrScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          NewDeliveryBanner(
            deliveries: watch.pending,
            onViewBoard: _openBoard,
            onDismiss: watch.clear,
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                DashboardTab(),
                CommissionListTab(),
                RewardsTab(),
                LocationTab(),
                ProfileTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: S.tabHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: S.tabCommission,
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: S.tabRewards,
          ),
          NavigationDestination(
            icon: Icon(Icons.my_location_outlined),
            selectedIcon: Icon(Icons.my_location),
            label: S.tabLocation,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: S.tabProfile,
          ),
        ],
      ),
    );
  }
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  SummaryDto? _summary;
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
      final result = await AppScope.of(context).repository.summary();
      if (!mounted) return;
      setState(() {
        _summary = result.value;
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
    final profile = AppScope.of(context).auth.profile;
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final s = _summary!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_stale) OfflineBanner(cachedAt: _cachedAt),
          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                profile?.name ?? S.dash,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(S.idLine(profile?.id ?? S.dash)),
              trailing: const Icon(Icons.qr_code_2, color: Colors.teal),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QrScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.grid_view, color: Colors.teal),
              title: const Text(
                S.myBoard,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(S.myBoardSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeliveryBoardScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.55,
            children: [
              StatCard(
                label: S.successfulDeliveries,
                value: '${s.successfulDeliveries}',
                icon: Icons.local_shipping,
              ),
              StatCard(
                label: S.commissionEarned,
                amount: s.commissionEarned,
                color: Colors.teal,
                icon: Icons.savings,
              ),
              StatCard(
                label: S.commissionPaid,
                amount: s.commissionPaid,
                color: Colors.green,
                icon: Icons.payments,
              ),
              StatCard(
                label: S.unpaidCommission,
                amount: s.unpaidCommission,
                color: s.unpaidCommission > 0 ? Colors.red : Colors.grey,
                icon: Icons.pending_actions,
              ),
              StatCard(
                label: S.rewardsEarned,
                amount: s.rewardsEarned,
                color: Colors.amber.shade800,
                icon: Icons.emoji_events,
              ),
              StatCard(
                label: S.rewardsPaid,
                amount: s.rewardsPaid,
                color: Colors.green,
                icon: Icons.redeem,
              ),
              StatCard(
                label: S.unpaidRewards,
                amount: s.unpaidRewards,
                color: s.unpaidRewards > 0 ? Colors.red : Colors.grey,
                icon: Icons.hourglass_bottom,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.totalsNote,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
