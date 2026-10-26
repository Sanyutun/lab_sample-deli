import 'dart:io';

import 'package:flutter/material.dart';

import '../core/office_link.dart';
import 'scan_office_qr_screen.dart';

/// Camera scanning is available where mobile_scanner has a platform plugin;
/// the desktop office terminal types the address instead.
bool _cameraScanSupported() =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Asks where this terminal should keep its data: its own database, or another
/// office terminal reached over the LAN.
///
/// Returns the chosen link, or null when the user cancels. Choosing "This
/// device" returns [OfficeLink.local].
Future<OfficeLink?> showOfficeLinkDialog(
  BuildContext context,
  OfficeLink current,
) {
  final urlController = TextEditingController(text: current.url);
  final keyController = TextEditingController(text: current.key);
  return showDialog<OfficeLink>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Office server'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the address and link key shown on the host terminal '
              '(Companion Sync Server screen), or scan its QR code. Leave '
              'empty to use this device\'s own database.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'http://192.168.1.5:8787',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Link key',
                border: OutlineInputBorder(),
              ),
            ),
            if (_cameraScanSupported()) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final scanned = await Navigator.of(ctx).push<OfficeLink>(
                      MaterialPageRoute(
                        builder: (_) => const ScanOfficeQrScreen(),
                      ),
                    );
                    if (scanned == null || !ctx.mounted) return;
                    urlController.text = scanned.url;
                    if (scanned.key.isNotEmpty) {
                      keyController.text = scanned.key;
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Address scanned — now enter the link key.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, OfficeLink.local),
          child: const Text('This device'),
        ),
        FilledButton(
          onPressed: () {
            final raw = urlController.text.trim();
            // Accept "192.168.1.5:8787" as well as a full URL; HttpStorage
            // cannot guess the scheme and would fail with an unsupported one.
            final url =
                raw.isEmpty ||
                    raw.startsWith('http://') ||
                    raw.startsWith('https://')
                ? raw
                : 'http://$raw';
            Navigator.pop(
              ctx,
              current.copyWith(url: url, key: keyController.text.trim()),
            );
          },
          child: const Text('Connect'),
        ),
      ],
    ),
  );
}
