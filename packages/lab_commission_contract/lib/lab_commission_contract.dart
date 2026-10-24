/// Shared API contract between the office (backend) app and the delivery-man
/// companion app. Keeping the DTOs and the QR token rules in one place means the
/// two apps cannot drift apart: the office server encodes exactly what the
/// companion decodes.
library;

export 'src/api_routes.dart';
export 'src/dto.dart';
export 'src/qr_token.dart';
