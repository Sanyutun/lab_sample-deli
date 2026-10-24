import 'package:lab_commission_contract/lab_commission_contract.dart';

/// The complete read surface the companion app is allowed to use, plus login,
/// logout, its own QR identity and GPS logging.
///
/// Note what is *not* here: there is no method to create or edit a commission,
/// a payment, a reward or a rule. The app physically cannot change money.
abstract class CompanionApi {
  /// Bearer token attached to authenticated calls. Set by the auth controller.
  String? token;

  Future<AuthSessionDto> login({required String loginId, required String pin});
  Future<void> logout();

  Future<DeliveryManProfileDto> me();
  Future<SummaryDto> summary();
  Future<List<CommissionDto>> commissions({
    String? from,
    String? to,
    String? status,
  });
  Future<CommissionDto> commission(String id);
  Future<List<RewardDto>> rewards();

  /// This man's own delivery board. The server scopes it to the session, so it
  /// can never contain another man's deliveries.
  Future<DeliveryBoardDto> deliveryBoard();

  Future<QrIdentityDto> qr();

  /// The office-wide GPS policy this phone must follow.
  Future<GpsPolicyDto> gpsPolicy();

  Future<List<GeoPointDto>> locations();
  Future<GeoPointDto> recordLocation({
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? capturedAt,
    String? barcode,
    String? clientId,
  });
}
