import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/core/office_link.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/main.dart';
import 'package:lab_commission/ui/office_link_dialog.dart';

void main() {
  test('office setup QR carries the address and link key', () {
    const link = OfficeLink(
      url: 'http://192.168.1.20:8787',
      key: 'abc+/=123',
    );
    final scanned = OfficeLink.fromScanned(link.qrPayload);
    expect(scanned?.url, 'http://192.168.1.20:8787');
    expect(scanned?.key, 'abc+/=123');
    expect(scanned?.isConfigured, isTrue);
  });

  test('the scanner accepts a plain server address', () {
    expect(
      OfficeLink.fromScanned('http://192.168.1.20:8787')?.url,
      'http://192.168.1.20:8787',
    );
    expect(
      OfficeLink.fromScanned('192.168.1.20:8787')?.url,
      'http://192.168.1.20:8787',
    );
  });

  test('the scanner rejects QR codes that are not office servers', () {
    expect(OfficeLink.fromScanned(''), isNull);
    expect(OfficeLink.fromScanned('hello'), isNull);
    expect(OfficeLink.fromScanned('http://example.com'), isNull);
  });

  testWidgets('The login screen says where its data comes from', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    expect(find.text('Server: this device (local)'), findsOneWidget);
  });

  testWidgets('An unreachable office server shows a way back, not a dead app', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      LabCommissionApp(
        link: const OfficeLink(url: 'http://192.168.1.5:8787', key: 'k'),
        loader: (_) async {
          attempts++;
          if (attempts == 1) {
            throw Exception('Cannot reach the office server');
          }
          return AppServices.bootstrap(MemoryStorage());
        },
      ),
    );
    await tester.pumpAndSettle();

    // The failure is stated, with the offending address and both ways out.
    expect(find.text('Cannot open the office data'), findsOneWidget);
    expect(find.textContaining('http://192.168.1.5:8787'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Server settings'), findsOneWidget);

    // Retry reaches the server, so the app opens on the configured link.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot open the office data'), findsNothing);
    expect(find.text('TWOK Sample Deli - Office'), findsOneWidget);
    expect(find.text('Server: http://192.168.1.5:8787'), findsOneWidget);
  });

  testWidgets('Server settings opens from the connection error screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      LabCommissionApp(
        link: const OfficeLink(url: 'http://192.168.1.5:8787', key: 'k'),
        loader: (_) async => throw Exception('Cannot reach the office server'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cannot open the office data'), findsOneWidget);

    // The way to point the app at a new IP must actually open.
    await tester.tap(find.text('Server settings'));
    await tester.pumpAndSettle();

    expect(find.text('Office server'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    final address = tester.widget<TextField>(find.byType(TextField).first);
    expect(address.controller?.text, 'http://192.168.1.5:8787');
  });

  testWidgets('A server address typed without http:// still works', (
    tester,
  ) async {
    OfficeLink? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await showOfficeLinkDialog(context, OfficeLink.local);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '192.168.1.5:8787');
    await tester.enterText(find.byType(TextField).last, 'link-key');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(chosen?.url, 'http://192.168.1.5:8787');
    expect(chosen?.key, 'link-key');
  });
}
