import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../domain/dashboard_features.dart';
import 'admin_screens.dart';
import 'call_log_screen.dart';
import 'cash_screens.dart';
import 'common.dart';
import 'companion_screens.dart';
import 'delivery_man_screen.dart';
import 'finance_screen.dart';
import 'history_screens.dart';
import 'login_screen.dart';
import 'print_monitor_screen.dart';
import 'route_analysis_screen.dart';
import 'scan_flow.dart';
import 'successful_delivery_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.userName,
    required this.isAdmin,
  });

  final String userName;
  final bool isAdmin;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, String> _settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppScope.of(context).settings.all();
    if (mounted) setState(() => _settings = all);
  }

  /// Admin Settings toggles these; a missing key means shown.
  bool _visible(DashboardFeature feature, {required bool admin}) =>
      feature.alwaysVisible ||
      _settings[feature.visibilityKey(admin: admin)] != '0';

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    // Pick up any dashboard-button changes made in Admin Settings.
    await _load();
  }

  static Widget _screenFor(DashboardFeature feature) => switch (feature) {
    DashboardFeature.printMonitor => const PrintMonitorScreen(),
    DashboardFeature.scanReceipt => const ScanReceiptScreen(),
    DashboardFeature.deliveryBoard => const SuccessfulDeliveryScreen(),
    DashboardFeature.deliveryHistory => const DeliveryHistoryScreen(),
    DashboardFeature.callLog => const CallLogScreen(),
    DashboardFeature.cashClosing => const FinanceScreen(),
    DashboardFeature.commissionHistory => const CommissionHistoryScreen(),
    DashboardFeature.deliveryMen => const DeliveryManManagementScreen(),
    DashboardFeature.companionAccounts => const CompanionAccountsScreen(),
    DashboardFeature.companionServer => const CompanionServerScreen(),
    DashboardFeature.routeAnalysis => const RouteAnalysisScreen(),
    DashboardFeature.cashAdvance => const CashAdvanceScreen(),
    DashboardFeature.receiptImport => const OfficialReceiptImportScreen(),
    DashboardFeature.reconciliation => const ReconciliationScreen(),
    DashboardFeature.googleSheets => const SheetsSyncScreen(),
    DashboardFeature.auditLog => const AuditLogScreen(),
    DashboardFeature.adminSettings => const AdminSettingsScreen(),
  };

  static IconData _iconFor(DashboardFeature feature) => switch (feature) {
    DashboardFeature.printMonitor => Icons.print,
    DashboardFeature.scanReceipt => Icons.qr_code_scanner,
    DashboardFeature.deliveryBoard => Icons.dashboard_customize,
    DashboardFeature.deliveryHistory => Icons.history,
    DashboardFeature.callLog => Icons.call,
    DashboardFeature.cashClosing => Icons.account_balance_wallet,
    DashboardFeature.commissionHistory => Icons.receipt_long,
    DashboardFeature.deliveryMen => Icons.groups,
    DashboardFeature.companionAccounts => Icons.phone_android,
    DashboardFeature.companionServer => Icons.wifi_tethering,
    DashboardFeature.routeAnalysis => Icons.explore,
    DashboardFeature.cashAdvance => Icons.payments,
    DashboardFeature.receiptImport => Icons.upload_file,
    DashboardFeature.reconciliation => Icons.compare_arrows,
    DashboardFeature.googleSheets => Icons.table_chart,
    DashboardFeature.auditLog => Icons.policy,
    DashboardFeature.adminSettings => Icons.settings,
  };

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;
    final quickScan = isWindows
        ? DashboardFeature.printMonitor
        : DashboardFeature.scanReceipt;
    final items = [
      for (final feature in DashboardFeature.values)
        if ((!feature.adminOnly || widget.isAdmin) &&
            (!feature.windowsOnly || isWindows) &&
            (!feature.androidOnly || !isWindows) &&
            _visible(feature, admin: widget.isAdmin))
          feature,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard · ${widget.userName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await AppScope.of(context).auth.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isAdmin && _visible(quickScan, admin: true))
            Card(
              color: Colors.teal.shade50,
              child: ListTile(
                leading: const Icon(Icons.add_a_photo, color: Colors.teal),
                title: Text(
                  isWindows ? 'Print monitor' : 'Quick scan',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  isWindows
                      ? 'Print job → delivery man → commission → confirm'
                      : 'Scan → delivery man → commission → confirm',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(_screenFor(quickScan)),
              ),
            ),
          const SizedBox(height: 8),
          AutoGrid(
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              for (final feature in items)
                Card(
                  child: InkWell(
                    onTap: () => _open(_screenFor(feature)),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_iconFor(feature), size: 30, color: Colors.teal),
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                              feature.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
