import 'strings.dart';

/// Errors the UI can show directly. Kept small and typed so screens can decide
/// between "retry", "sign in again" and "you are offline".
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// No usable network connection, or the server could not be reached.
class OfflineFailure extends AppFailure {
  const OfflineFailure([super.message = S.errOffline]);
}

/// The session token is missing, expired or revoked.
class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = S.errSession]);
}

/// Any other error the server returned.
class ApiFailure extends AppFailure {
  const ApiFailure(this.code, String message) : super(message);
  final String code;
}

/// GPS could not provide a usable fix.
class LocationFailure extends AppFailure {
  const LocationFailure(super.message);
}

/// A permission problem reported by the device (e.g. location denied).
class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message);
}
