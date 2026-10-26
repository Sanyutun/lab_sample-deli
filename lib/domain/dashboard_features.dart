/// A button on the office dashboard that an admin can hide per role.
///
/// Visibility lives in the settings table under [visibilityKey]; a missing key
/// means visible, so new buttons show up until an admin turns them off.
enum DashboardFeature {
  printMonitor('Print Monitor', windowsOnly: true),
  scanReceipt('Scan Receipt', androidOnly: true),
  deliveryBoard('Delivery Board'),
  deliveryHistory('Delivery History'),
  callLog('Call Log'),
  cashClosing('Cash & Closing'),

  commissionHistory('Commission History', adminOnly: true),
  deliveryMen('Delivery Men', adminOnly: true),
  companionAccounts('Companion Accounts', adminOnly: true),
  companionServer('Companion Server', adminOnly: true),
  routeAnalysis('Route Analysis', adminOnly: true),
  cashAdvance('Cash Advance', adminOnly: true),
  receiptImport('Receipt Import', adminOnly: true),
  reconciliation('Reconciliation', adminOnly: true),
  googleSheets('Google Sheets', adminOnly: true),
  auditLog('Audit Log', adminOnly: true),

  /// Always shown to admins: hiding it would leave no way back to settings.
  adminSettings('Admin Settings', adminOnly: true, alwaysVisible: true);

  const DashboardFeature(
    this.label, {
    this.adminOnly = false,
    this.windowsOnly = false,
    this.androidOnly = false,
    this.alwaysVisible = false,
  });

  /// Button caption on the dashboard.
  final String label;

  /// Admins only by default; an admin can still tick the Staff box in Admin
  /// Settings to let staff open it.
  final bool adminOnly;

  final bool windowsOnly;
  final bool androidOnly;

  /// Cannot be hidden by anyone.
  final bool alwaysVisible;

  String visibilityKey({required bool admin}) =>
      'dashboard.$name.${admin ? 'admin' : 'staff'}';
}
