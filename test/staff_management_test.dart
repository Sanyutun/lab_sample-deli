import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/exceptions.dart';
import 'package:lab_commission/ui/admin_screens.dart';

Future<AppServices> _pumpAdmin(
  WidgetTester tester, {
  Future<void> Function(AppServices services)? setup,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final services = await AppServices.bootstrap(MemoryStorage());
  await services.auth.login('1234');
  await setup?.call(services);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: const MaterialApp(home: AdminSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

Future<void> _openAddStaff(WidgetTester tester) async {
  await tester.ensureVisible(find.text('ADD STAFF'));
  await tester.tap(find.text('ADD STAFF'));
  await tester.pumpAndSettle();
}

Future<void> _fillNewStaff(
  WidgetTester tester, {
  required String name,
  required String pin,
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Staff name'), name);
  await tester.enterText(
    find.widgetWithText(TextField, 'Login PIN (4 to 8 digits)'),
    pin,
  );
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('ADD STAFF'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin adds a staff member who can sign in with their own PIN', (
    tester,
  ) async {
    final services = await _pumpAdmin(tester);
    await _openAddStaff(tester);

    expect(find.text('Add staff'), findsOneWidget);
    await _fillNewStaff(tester, name: 'Aye Chan', pin: '2468');

    // Adding a login is sensitive, so the current admin PIN is asked for.
    expect(find.text('Admin approval needed'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Admin PIN'), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    final added = (await services.users.all()).firstWhere(
      (u) => u.name == 'Aye Chan',
    );
    expect(added.role, UserRole.staff);
    expect(added.pin, '2468');
    expect(added.active, isTrue);
    expect(added.lastLoginAt, isNull);
    expect(find.textContaining('login PIN 2468'), findsOneWidget);
    expect(
      (await services.audit.logs()).where((l) => l.action == 'USER_ADDED'),
      hasLength(1),
    );

    // The new account keeps its own identity and records its first sign-in.
    await services.auth.logout();
    final signedIn = await services.auth.login('2468');
    expect(signedIn.name, 'Aye Chan');
    expect(signedIn.lastLoginAt, isNotNull);
    expect((await services.users.findById(added.id))!.lastLoginAt, isNotNull);
  });

  testWidgets('a PIN already in use cannot be given to another staff member', (
    tester,
  ) async {
    final services = await _pumpAdmin(tester);
    await _openAddStaff(tester);

    // 1111 belongs to the seeded Staff account.
    await _fillNewStaff(tester, name: 'Twin', pin: '1111');

    expect(find.text('That PIN is already used by Staff'), findsOneWidget);
    expect(find.text('Add staff'), findsOneWidget);
    expect(find.text('Admin approval needed'), findsNothing);
    expect(
      (await services.users.all()).where((u) => u.name == 'Twin'),
      isEmpty,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'deactivating a staff member blocks sign-in but keeps the account',
    (tester) async {
      late User leaver;
      final services = await _pumpAdmin(
        tester,
        setup: (s) async {
          leaver = await s.users.create(
            name: 'Ko Leaver',
            pin: '9753',
            role: UserRole.staff,
          );
        },
      );

      final tile = find.ancestor(
        of: find.text('Ko Leaver'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(tile);
      await tester.tap(
        find.descendant(of: tile, matching: find.byTooltip('Deactivate staff')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Admin PIN'),
        '1234',
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      final saved = await services.users.findById(leaver.id);
      expect(saved, isNotNull);
      expect(saved!.active, isFalse);
      expect(find.textContaining('INACTIVE'), findsOneWidget);
      expect(
        (await services.audit.logs()).where(
          (l) => l.action == 'USER_DEACTIVATED',
        ),
        hasLength(1),
      );

      await services.auth.logout();
      await expectLater(
        services.auth.login('9753'),
        throwsA(isA<PermissionDeniedException>()),
      );
    },
  );

  test(
    'a legacy duplicate PIN still signs an active user in so it can be fixed',
    () async {
      final services = await AppServices.bootstrap(MemoryStorage());
      final staff = (await services.users.all()).firstWhere(
        (u) => u.pin == '1111',
      );

      // Simulate a database written before PIN uniqueness was enforced.
      await services.storage.insert(
        'users',
        User(
          id: 'usr_legacy_duplicate',
          name: 'Legacy Duplicate',
          pin: staff.pin,
          role: UserRole.staff,
        ).toMap(),
      );

      final signedIn = await services.auth.login('1111');
      expect(signedIn.pin, '1111');
      expect(signedIn.active, isTrue);
    },
  );

  test('changing a PIN to one already in use is refused', () async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final staff = (await services.users.all()).firstWhere(
      (u) => u.pin == '1111',
    );

    await expectLater(
      services.users.update(staff.copyWith(pin: '1234')),
      throwsA(isA<ValidationException>()),
    );
  });

  test('creating an account rejects a short or non-numeric PIN', () async {
    final services = await AppServices.bootstrap(MemoryStorage());

    for (final pin in ['123', '12ab', '123456789']) {
      await expectLater(
        services.users.create(name: 'Bad PIN', pin: pin, role: UserRole.staff),
        throwsA(isA<ValidationException>()),
      );
    }
  });
}
