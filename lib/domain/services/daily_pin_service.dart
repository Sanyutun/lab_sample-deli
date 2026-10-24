import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';

import '../../data/models/models.dart';
import '../../data/repositories/daily_pin_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/user_repository.dart';
import 'audit_service.dart';
import 'google_sheets_service.dart';

/// One fresh 6-digit action PIN per active user per calendar day.
///
/// The PIN is asked only for money-changing actions (delete, take a payment
/// back, correct). It is kept locally so the office still works offline and
/// written to the [sheetName] worksheet with each user's Gmail. The Apps Script
/// installed in that spreadsheet (see `tool/daily_pin_gsheet.gs`) sends the
/// PIN from the sheet owner's Gmail, so the app needs no Gmail password.
class DailyPinService {
  DailyPinService(
    this._pins,
    this._users,
    this._settings,
    this._sheets,
    this._audit,
  );

  final DailyPinRepository _pins;
  final UserRepository _users;
  final SettingsRepository _settings;
  final GoogleSheetsService _sheets;
  final AuditService _audit;

  /// Shared setting so terminals on one office database write only once a day.
  static const String publishedKey = 'pins.publishedDate';
  static const String sheetName = 'DailyPins';
  static const List<String> sheetHeaders = [
    'Date',
    'Time',
    'User ID',
    'Name',
    'Role',
    'Email',
    'PIN',
    'Sent',
  ];

  static final Random _random = Random.secure();
  String? _ensuredDate;
  Future<String?>? _scheduled;

  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Creates today's missing PINs (once per run) and starts sending them in the
  /// background. Safe to call often: a day that is already done returns at once.
  /// Returns true only when this call generated new PINs.
  Future<bool> ensureToday() async {
    final day = today;
    if (_ensuredDate == day) return false;
    try {
      final users = (await _users.all()).where((u) => u.active).toList();
      final current = {
        for (final p in await _pins.all())
          if (p.date == day) p.userId: p,
      };
      final used = {for (final p in current.values) p.pin};
      final generated = <DailyPin>[];
      for (final user in users) {
        if (current.containsKey(user.id)) continue;
        var pin = _randomPin();
        while (used.contains(pin)) {
          pin = _randomPin();
        }
        used.add(pin);
        final daily = DailyPin(
          userId: user.id,
          pin: pin,
          date: day,
          generatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _pins.save(daily);
        generated.add(daily);
      }
      _ensuredDate = day;
      if (generated.isNotEmpty) {
        _scheduled = publishToday();
        unawaited(_scheduled!);
      }
      return generated.isNotEmpty;
    } catch (e) {
      // A bad PIN table must not stop the app or a delivery being recorded.
      try {
        await _audit.record('DAILY_PINS_FAILED', newValue: '$e');
      } catch (_) {}
      return false;
    }
  }

  /// Writes today's PINs to the sheet for its Apps Script to email. Returns
  /// null when another office terminal already did it today; [force] is used by
  /// RESEND.
  Future<String?> publishToday({bool force = false}) async {
    final day = today;
    try {
      if (!force && await _settings.get(publishedKey) == day) return null;
      final pins = (await _pins.all()).where((p) => p.date == day).toList();
      if (pins.isEmpty) return 'No PINs have been created for today.';
      // Marked before writing so a crash cannot make every terminal write.
      await _settings.set(publishedKey, day);
      return await _publish(pins);
    } catch (e) {
      return 'Could not write today\'s PINs to Google Sheets: $e';
    }
  }

  /// The PIN [userId] must enter today, or null when they have none.
  Future<String?> currentPin(String userId) async {
    await ensureToday();
    final row = (await _pins.all()).where(
      (p) => p.userId == userId && p.date == today,
    );
    return row.isEmpty ? null : row.first.pin;
  }

  /// True when [pin] is the current user's PIN for today.
  Future<bool> verify(String userId, String pin) async {
    await ensureToday();
    final clean = pin.trim();
    if (clean.isEmpty) return false;
    final row = (await _pins.all()).where(
      (p) => p.userId == userId && p.date == today,
    );
    return row.isNotEmpty && row.first.pin == clean;
  }

  /// Appends today's PINs to the sheet again without changing them, so the Apps
  /// Script mails them once more. Used by Admin Settings when a mail did not
  /// arrive.
  Future<String> resendToday() async {
    final generated = await ensureToday();
    final pending = _scheduled;
    if (pending != null) {
      final auto = await pending;
      if (generated && auto != null) return auto;
    }
    return await publishToday(force: true) ??
        'No PINs have been created for today.';
  }

  Future<String> _publish(List<DailyPin> pins) async {
    if (!_sheets.config.isConfigured) {
      return 'Google Sheets is not configured, so today\'s PINs were not '
          'written for the Apps Script to email.';
    }
    final users = {for (final u in await _users.all()) u.id: u};
    try {
      await _writeSheet(pins, users);
    } catch (e) {
      await _audit.record('DAILY_PINS_SHEET_FAILED', newValue: '$e');
      return 'Could not save today\'s PINs to Google Sheets: $e';
    }
    final withEmail = pins
        .where((p) => (users[p.userId]?.email.trim() ?? '').isNotEmpty)
        .length;
    if (withEmail == 0) {
      return 'Today\'s PINs are saved to the $sheetName sheet, but no active '
          'user has a Gmail address, so the Apps Script has nothing to send.';
    }
    return 'Today\'s PINs are saved to the $sheetName sheet. Its Apps Script '
        'will Gmail them to $withEmail user(s) within a minute.';
  }

  Future<void> _writeSheet(List<DailyPin> pins, Map<String, User> users) async {
    final spreadsheetId = _sheets.config.spreadsheetId;
    final titles = await _sheets.client.sheetTitles(
      spreadsheetId: spreadsheetId,
    );
    final fresh = !titles.contains(sheetName);
    if (fresh) {
      await _sheets.client.addSheets(
        spreadsheetId: spreadsheetId,
        titles: [sheetName],
      );
    } else {
      // Upgrade a DailyPins tab written by an older build: it had the PIN in
      // column F and no Email/Sent columns. Old rows are marked as sent so the
      // script never mails yesterday's PINs.
      final existing = await _sheets.client.read(
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
      );
      if (existing.isEmpty || !_isCurrentHeader(existing.first)) {
        await _sheets.client.overwrite(
          spreadsheetId: spreadsheetId,
          sheetName: sheetName,
          rows: [
            sheetHeaders,
            for (final row in existing.skip(1)) _upgradeRow(row),
          ],
        );
      }
    }
    await _sheets.client.appendRows(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      rows: [
        if (fresh) sheetHeaders,
        for (final pin in pins)
          if (users[pin.userId] case final user?)
            [
              pin.date,
              DateFormat('HH:mm')
                  .format(DateTime.fromMillisecondsSinceEpoch(pin.generatedAt)),
              user.id,
              user.name,
              user.role.name,
              user.email.trim(),
              pin.pin,
              '',
            ],
      ],
    );
  }

  static bool _isCurrentHeader(List<String> row) =>
      row.length >= sheetHeaders.length &&
      [for (var i = 0; i < sheetHeaders.length; i++) row[i] == sheetHeaders[i]]
          .every((same) => same);

  /// Old layout: Date, Time, User ID, Name, Role, PIN.
  static List<Object?> _upgradeRow(List<String> row) {
    if (row.length == 6) {
      return [row[0], row[1], row[2], row[3], row[4], '', row[5], 'migrated'];
    }
    return [...row, for (var i = row.length; i < sheetHeaders.length; i++) ''];
  }

  static String _randomPin() => (100000 + _random.nextInt(900000)).toString();
}
