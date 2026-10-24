/// Every word the delivery man reads, in one place.
///
/// The app has a single language at a time: these constants *are* the interface
/// text. Keeping them together means wording can be checked and corrected
/// without hunting through screens, and it stops the same phrase drifting into
/// two versions. To change the language, edit this file only.
///
/// Money and dates are still formatted by [fmtMMK] / [fmtDateTime].
class S {
  S._();

  // ---- general ----
  static const appName = 'TWOK Sample Delivery Man';
  static const dash = '—';
  static const tryAgain = 'Try again';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const notSet = 'Not set';

  // ---- navigation ----
  static const tabHome = 'Home';
  static const tabCommission = 'Commission';
  static const tabRewards = 'Rewards';
  static const tabLocation = 'Location';
  static const tabProfile = 'Profile';
  static const titleDashboard = 'Dashboard';
  static const titleCommission = 'My commission';
  static const titleRewards = 'My rewards';
  static const titleLocation = 'Location';
  static const titleProfile = 'Profile';
  static const myQrTitle = 'My QR code';
  static const settingsTitle = 'Settings & logout';

  // ---- login ----
  static const loginSubtitle = 'Sign in with the ID and PIN from your office';
  static const deliveryId = 'Delivery ID';
  static const pin = 'PIN';
  static const signIn = 'SIGN IN';
  static const setServerAddress = 'Set office server address';
  static String serverLabel(String url) => 'Server: $url';

  // ---- dashboard ----
  static const idLabel = 'ID';
  static String idLine(String id) => 'ID: $id';
  static const myBoard = 'My delivery board';
  static const myBoardSubtitle = 'Your delivery positions and rewards';
  static const successfulDeliveries = 'Successful deliveries';
  static const commissionEarned = 'Commission earned';
  static const commissionPaid = 'Commission paid';
  static const unpaidCommission = 'Unpaid commission';
  static const rewardsEarned = 'Rewards earned';
  static const rewardsPaid = 'Rewards paid';
  static const unpaidRewards = 'Unpaid rewards';
  static const unpaidBalance = 'Unpaid balance';
  static const totalsNote =
      'Totals are derived from the deliveries and payments the office has '
      'recorded — nothing is added on this phone.';

  // ---- delivery board ----
  static const boardTitle = 'My delivery board';
  static const refresh = 'Refresh';
  static const successfulOverPositions = 'Successful / positions';
  static String groupCounter(int group, int current, int total) =>
      'Group $group  ·  $current / $total';
  static String groupHeading(int n) => 'Group $n';
  static String deliveriesRange(int start, int end) => 'Deliveries $start–$end';
  static String groupSummary(int done, String total) =>
      '$done/10 successful · $total';
  static const jumpToGroup = 'Jump to group #';
  static String groupHasNoDeliveries(int n) =>
      'Group $n has no deliveries yet.';
  static const emptyPositionNote =
      'Empty position. Deliveries are recorded by the office, not on this '
      'phone.';
  static const firstGroup = 'First group';
  static const previousGroup = 'Previous group';
  static const nextGroup = 'Next group';
  static const lastGroup = 'Last group';
  static const noDeliveriesYet = 'No deliveries yet.';
  static const boardFootnote =
      'Positions are shown for reference only. The office records and pays '
      'every delivery; nothing here can be changed from this phone.';

  // ---- one delivery ----
  static const deliveryNumber = 'Delivery';
  static const receiptBarcode = 'Receipt barcode';
  static const commissionLabel = 'Commission';
  static const recordedAt = 'Recorded at';
  static const paymentStatus = 'Payment status';
  static const officialReceipt = 'Official receipt';
  static const paidOn = 'Paid on';
  static const deliveryTime = 'Delivery time';
  static const paymentHistory = 'Payment history';
  static const noPaymentsYet = 'No payments recorded yet';
  static const officeKeepsRecord =
      'This record is kept by the office. It cannot be changed from this '
      'phone.';
  static const deliveryDetails = 'Delivery details';
  static const stateSuccessful = 'SUCCESSFUL';
  static const statePending = 'PENDING VERIFICATION';
  static const stateReversed = 'DELETED';
  static const stateEmpty = 'EMPTY';
  static const badgePaid = 'PAID';
  static const badgeUnpaid = 'UNPAID';
  static const badgeReversed = 'REV';

  // ---- commission list ----
  static const anyDate = 'Any date';
  static const clearDateFilter = 'Clear date filter';
  static const filterAll = 'All';
  static const filterUnpaid = 'Unpaid';
  static const filterPaid = 'Paid';
  static const noDeliveriesMatch = 'No deliveries match this filter yet.';

  // ---- rewards ----
  static const noRewardsYet =
      'No rewards yet. The office adds one each time you reach a delivery '
      'milestone.';
  static const rewardsNote =
      'Rewards are separate from commission and are created by the office '
      'from its own milestone rules. They cannot be added or changed here.';
  static String reachedAt(int count) => 'Reached at $count deliveries';
  static String paidOnDate(String date) => 'Paid $date';
  static String addedOnDate(String date) => 'Added $date';
  static String everyNDeliveries(int n, String amount) =>
      'Every $n deliveries → $amount';

  // ---- location ----
  static const locationOn = 'Location sharing is on';
  static const locationOff = 'Location sharing is off';
  static String locationOnNote(String every) =>
      'While you are signed in this phone sends your location to the office '
      'about every $every. The ongoing notification shows when it is running.';
  static const locationOffNote = 'Fixes are not being captured right now.';
  static const batteryWarning =
      'Android may stop background location to save battery on this phone. '
      'Allow this app to run without battery optimisation so tracking keeps '
      'working with the screen off.';
  static const allowBackground = 'Allow background tracking';
  static const openSettings = 'Open settings';
  static String lastSent(String at) => 'Last sent $at';
  static String allFixesSent(String retention) =>
      'All fixes have been sent to the office. Sent points are kept on the '
      'phone for the last $retention, then removed.';
  static String fixesWaiting(int count) =>
      '$count fix(es) waiting to be sent — they go automatically when the '
      'office server is reachable. Nothing is deleted until the office '
      'confirms it has them.';
  static const sendNow = 'Send now';
  static const sent = 'Sent';
  static const waiting = 'Waiting';
  static const noLocationsYet = 'No locations captured yet.';

  // ---- profile ----
  static const deliveryIdLabel = 'Delivery ID';
  static const phone = 'Phone';
  static const officeServer = 'Office server';
  static const settingsAndLogout = 'Settings & logout';
  static const profileNote =
      'Your name and ID are managed by the office. Contact them to correct '
      'any detail.';

  // ---- settings ----
  static const officeServerAddress = 'Office server address';
  static const notSetTapToEnter = 'Not set — tap to enter it';
  static const locationCaptured = 'Location is captured';
  static String aboutEvery(String every) =>
      'About every $every — set by the office';
  static const sentLocationsKept = 'Sent locations kept on this phone';
  static String setByOffice(String retention) =>
      '$retention — set by the office';
  static const readOnlyNote =
      'This app is read-only: it shows the deliveries, commission and rewards '
      'the office has recorded for you. It cannot create or change any '
      'payment, commission or reward.';
  static const logout = 'Log out';
  static const logoutQuestion = 'Log out?';
  static const logoutBody =
      'Your saved figures and session will be removed from this phone. You '
      'will need your ID and PIN to sign in again.';

  // ---- server dialog / QR scan ----
  static const serverDialogHelp =
      'Enter the address shown on the office app\'s Companion Server screen, '
      'for example 192.168.1.20:8787, or scan its QR code.';
  static const serverAddress = 'Server address';
  static const scanQr = 'Scan QR';
  static const notOfficeCode = 'That is not an office setup code';
  static const scanOfficeQr = 'Scan office QR';
  static const scanOfficeQrHelp =
      'Point the camera at the QR code on the office app\'s Companion Server '
      'screen.';

  // ---- QR screen ----
  static const showToStaff = 'Show this to office staff';
  static String issuedAt(String at) => 'Issued $at';
  static const qrOfflineNote =
      'You are offline. This is your last saved code and the office may reject '
      'it — reconnect and refresh before showing it.';
  static const qrInfoNote =
      'This code is only an identity check. The office still confirms your '
      'account before recording anything, and the code never contains money '
      'or personal details.';
  static const qrRotateNote =
      'Opening or refreshing this screen replaces the previous code. If you '
      'think your code was copied, refresh it.';
  static const newCode = 'New code';
  static const getNewCode = 'Get a new code';

  // ---- shared state views ----
  static const offlineNoData = 'Offline — showing your last synced data';
  static String offlineSince(String at) => 'Offline — showing data from $at';

  // ---- durations & labels (used by formatters) ----
  static const oneMinute = '1 minute';
  static String nMinutes(int m) => '$m minutes';
  static String nDays(int n) => n == 1 ? '1 day' : '$n days';
  static const entryAdvance = 'Advance';
  static const entryCommission = 'Commission payment';
  static const entryReward = 'Reward payment';
  static const entryOtherIn = 'Other (in)';
  static const entryOtherOut = 'Other (out)';
  static const recMatch = 'Verified (matched official receipt)';
  static const recMismatch = 'Mismatch with official receipt';
  static const recNotFound = 'Not found in official receipts';
  static const recDuplicate = 'Duplicate entry';
  static const recUnclaimed = 'Unclaimed';
  static const recNone = 'Not reconciled yet';
  static const accuracyUnknown = 'Accuracy not reported';
  static String accuracyMetres(String m) => 'Accurate to ±$m m';

  // ---- delivery man's own readable errors ----
  static const errOffline = 'No connection to the office server';
  static const errSession = 'Your session has ended. Sign in again.';
  static const errNoServer = 'No office server address is set';
  static const errTimeout = 'The office server did not respond in time';
  static const errBadResponse = 'The server replied in an unexpected format';
  static const errRequestFailed = 'Request failed';
  static String errRequestFailedWithCode(int code) => 'Request failed ($code)';

  // ---- GPS tracking state ----
  static const trackServiceOff =
      'Location services are switched off on this phone.';
  static const trackDenied = 'Location permission was denied.';
  static const trackBlocked =
      'Location permission is blocked. Allow it in Android settings.';
  static const trackStopped = 'Location updates stopped.';
  static const gpsTimeout = 'GPS timed out. Move to an open area and retry.';
  static const locationServicesOff = 'Location services are switched off.';

  // ---- ongoing (foreground) notification while tracking ----
  static const notifTitle = 'Location sharing is on';
  static const notifText =
      'Your location is being sent to the office while you are signed in.';
  static const notifChannel = 'Location sharing';

  // ---- notifications (new delivery found on refresh) ----
  static const newDeliveryTitle = 'New delivery';
  static String newDeliveryBody(String amount, String when, String status) =>
      '$amount · $when · $status';
  static String newDeliveriesTitle(int count) => '$count new deliveries';
  static const viewBoard = 'View board';
  static const dismiss = 'Dismiss';
}
