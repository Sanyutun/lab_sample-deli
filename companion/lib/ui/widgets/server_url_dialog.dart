import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/app_services.dart';
import '../../core/strings.dart';
import '../screens/scan_server_qr_screen.dart';

/// Lets the user type the office server address (IP:port or full URL), or scan
/// the office "setup QR". The office "Companion Server" screen shows both.
Future<bool> showServerUrlDialog(
  BuildContext context,
  AppServices services,
) async {
  final controller = TextEditingController(text: services.config.serverUrl);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(S.officeServerAddress),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(S.serverDialogHelp, style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: S.serverAddress,
              hintText: '192.168.1.20:8787',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final payload = await Navigator.push<String>(
                ctx,
                MaterialPageRoute(builder: (_) => const ScanServerQrScreen()),
              );
              if (payload == null) return;
              final url = AppConfig.serverUrlFromQr(payload);
              if (url == null) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text(S.notOfficeCode)),
                  );
                }
                return;
              }
              controller.text = url;
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text(S.scanQr),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(S.save),
        ),
      ],
    ),
  );
  if (result == true) {
    await services.config.saveServerUrl(controller.text);
    return true;
  }
  return false;
}
