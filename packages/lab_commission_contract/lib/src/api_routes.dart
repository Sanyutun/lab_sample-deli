/// Route and header names for the companion API, shared so the server and the
/// client can never disagree on a path.
library;

const String apiBasePath = '/api/v1';

/// Bearer token header used by every authenticated call.
const String authHeader = 'Authorization';
const String bearerPrefix = 'Bearer ';

class ApiRoutes {
  const ApiRoutes._();

  static const String login = '$apiBasePath/auth/login';
  static const String logout = '$apiBasePath/auth/logout';
  static const String me = '$apiBasePath/me';
  static const String summary = '$apiBasePath/me/summary';
  static const String commissions = '$apiBasePath/me/commissions';
  static String commission(String id) => '$commissions/$id';
  static const String rewards = '$apiBasePath/me/rewards';

  /// The signed-in man's own delivery board (read-only, his records only).
  static const String deliveryBoard = '$apiBasePath/me/delivery-board';
  static const String qr = '$apiBasePath/me/qr';
  static const String qrRotate = '$apiBasePath/me/qr/rotate';
  static const String locations = '$apiBasePath/me/locations';

  /// Office-wide GPS tracking policy the phone follows (how often a fix is
  /// captured, how long a sent fix is kept on the phone).
  static const String gpsPolicy = '$apiBasePath/gps-policy';

  /// Preserved GPS history (one route per delivered receipt). Scoped to the
  /// authenticated delivery man: he only ever sees his own trips.
  static const String trips = '$apiBasePath/me/trips';
  static String trip(String barcode) =>
      '$trips/${Uri.encodeComponent(barcode)}';

  /// Used by the office app to verify a scanned QR before assigning a receipt.
  static const String verifyQr = '$apiBasePath/verify-qr';

  /// Office-to-office data gateway. A second office terminal runs its own
  /// repositories against the host terminal's database through these routes.
  /// Authorised by the office link key (Bearer) — never by a delivery-man
  /// session — so it shares nothing with the companion surface above.
  static const String store = '$apiBasePath/store';
  static String storeOp(String op) => '$store/$op';
}
