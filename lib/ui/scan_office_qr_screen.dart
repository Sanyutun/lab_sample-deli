import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/office_link.dart';
import 'common.dart';

/// Scans the setup QR shown on the host office terminal's Companion Sync Server
/// screen. Returns the [OfficeLink] to connect to, or null when the user backs
/// out. Only reachable on phones/tablets, where the camera plugin is supported.
class ScanOfficeQrScreen extends StatefulWidget {
  const ScanOfficeQrScreen({super.key});

  @override
  State<ScanOfficeQrScreen> createState() => _ScanOfficeQrScreenState();
}

class _ScanOfficeQrScreenState extends State<ScanOfficeQrScreen> {
  bool _handled = false;

  void _handle(String payload) {
    if (_handled) return;
    _handled = true;
    final link = OfficeLink.fromScanned(payload);
    if (link == null) {
      _fail('That QR is not an office server code.');
      return;
    }
    Navigator.pop(context, link);
  }

  void _fail(String message) {
    if (!mounted) return;
    showMessage(context, message, error: true);
    setState(() => _handled = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Office QR')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.isNotEmpty
                    ? capture.barcodes.first.rawValue
                    : null;
                if (code != null && code.isNotEmpty) _handle(code);
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: const SafeArea(
              top: false,
              child: Text(
                'Point the camera at the QR code on the host office terminal '
                '(Companion Sync Server screen).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
