import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/repositories/daily_pin_repository.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/services/daily_pin_service.dart';
import 'package:lab_commission/domain/services/google_sheets_service.dart';

class _FakeSheets implements SheetsClient {
  String? sheetName;
  List<String> titles = [];
  List<List<String>> existing = [];
  List<List<Object?>> appended = [];
  List<List<Object?>> overwritten = [];

  @override
  Future<void> appendRows({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    this.sheetName = sheetName;
    appended.addAll(rows);
  }

  @override
  Future<void> addSheets({
    required String spreadsheetId,
    required List<String> titles,
  }) async {
    this.titles.addAll(titles);
  }

  @override
  Future<void> overwrite({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    this.sheetName = sheetName;
    overwritten = rows;
  }

  @override
  Future<List<List<String>>> read({
    required String spreadsheetId,
    required String sheetName,
  }) async => existing;

  @override
  Future<List<String>> sheetTitles({required String spreadsheetId}) async =>
      titles;
}

Future<AppServices> _servicesWithUsersOnSheet() async {
  final services = await AppServices.bootstrap(MemoryStorage());
  final users = (await services.users.all()).where((u) => u.active).toList();
  for (final user in users) {
    await services.users.update(user.copyWith(email: '${user.id}@example.com'));
  }
  services.sheets.client = _FakeSheets();
  services.sheets.config = const GoogleSheetsConfig(
    spreadsheetId: 'spreadsheet-1',
    serviceAccountJson: '{}',
  );
  return services;
}

void main() {
  test('each active user gets one stable 6-digit PIN for the day', () async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final users = (await services.users.all()).where((u) => u.active).toList();

    final pins = <String, String>{};
    for (final user in users) {
      final pin = await services.dailyPins.currentPin(user.id);
      expect(pin, isNotNull);
      expect(pin, matches(RegExp(r'^\d{6}$')));
      pins[user.id] = pin!;
    }
    expect(pins.values.toSet(), hasLength(users.length));
    expect(
      await services.dailyPins.currentPin(users.first.id),
      pins[users.first.id],
    );

    expect(
      await services.dailyPins.verify(users.first.id, pins[users.first.id]!),
      isTrue,
    );
    expect(await services.dailyPins.verify(users.first.id, '000000'), isFalse);
    if (users.length > 1) {
      expect(
        await services.dailyPins.verify(users.first.id, pins[users.last.id]!),
        isFalse,
      );
    }
  });

  test('the day rolling creates new PINs and rejects yesterday\'s', () async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final staff = (await services.users.all()).firstWhere((u) => !u.isAdmin);
    final oldPin = (await services.dailyPins.currentPin(staff.id))!;
    await services.storage.update(
      'daily_pins',
      {'user_id': staff.id},
      {'date': '2000-01-01'},
    );

    final fresh = DailyPinService(
      DailyPinRepository(services.storage),
      services.users,
      services.settings,
      services.sheets,
      services.audit,
    );
    expect(await fresh.ensureToday(), isTrue);
    final newPin = await fresh.currentPin(staff.id);
    expect(newPin, isNotNull);
    expect(newPin, isNot(oldPin));
    expect(await fresh.verify(staff.id, oldPin), isFalse);
    expect(await fresh.verify(staff.id, newPin!), isTrue);
  });

  test(
    'resend writes today\'s PINs and Gmail to the sheet for the Apps Script',
    () async {
      final services = await _servicesWithUsersOnSheet();
      final users = (await services.users.all())
          .where((u) => u.active)
          .toList();
      final sheet = services.sheets.client as _FakeSheets;

      final message = await services.dailyPins.resendToday();

      expect(message, contains(DailyPinService.sheetName));
      expect(message, contains('Apps Script'));
      expect(sheet.sheetName, DailyPinService.sheetName);
      expect(sheet.appended.first, DailyPinService.sheetHeaders);
      expect(sheet.appended, hasLength(users.length + 1));
      for (final user in users) {
        final pin = await services.dailyPins.currentPin(user.id);
        final row = sheet.appended.firstWhere((r) => r[2] == user.id);
        expect(row[5], '${user.id}@example.com');
        expect(row[6], pin);
        expect(row[7], isEmpty);
      }

      // A normal publish does not repeat an already-written day.
      expect(await services.dailyPins.publishToday(), isNull);
      expect(sheet.appended, hasLength(users.length + 1));
    },
  );

  test(
    'an old DailyPins sheet is upgraded without re-sending old PINs',
    () async {
      final services = await _servicesWithUsersOnSheet();
      final admin = (await services.users.all()).firstWhere((u) => u.isAdmin);
      final sheet = services.sheets.client as _FakeSheets;
      sheet.titles = [DailyPinService.sheetName];
      sheet.existing = [
        ['Date', 'Time', 'User ID', 'Name', 'Role', 'PIN'],
        ['2026-10-22', '09:00', admin.id, admin.name, 'admin', '111111'],
      ];

      await services.dailyPins.resendToday();

      expect(sheet.overwritten.first, DailyPinService.sheetHeaders);
      expect(sheet.overwritten[1], [
        '2026-10-22',
        '09:00',
        admin.id,
        admin.name,
        'admin',
        '',
        '111111',
        'migrated',
      ]);
      expect(sheet.appended.where((r) => r[6] == '111111'), isEmpty);
    },
  );
}
