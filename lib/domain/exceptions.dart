import '../data/models/models.dart';

class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

class DuplicateBarcodeException extends AppException {
  DuplicateBarcodeException(this.existing)
    : super(
        'Receipt already recorded. Existing: '
        '${existing.deliveryManName ?? existing.deliveryManId} · '
        '${existing.commission} MMK · ${existing.dateTimeLocal}',
      );

  final CommissionRecord existing;
}

class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message);
}

class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

class SheetsNotConfiguredException extends AppException {
  const SheetsNotConfiguredException()
    : super(
        'Google Sheets is not configured yet. Set spreadsheet ID and credentials first.',
      );
}
