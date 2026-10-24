import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/strings.dart';

/// Scans the office "setup QR" shown on the office app's Companion Server
/// screen. It encodes the sync-server URL (`http://<ip>:<port>`); this screen
/// only returns the raw payload — the caller validates and saves it.
class ScanServerQrScreen extends StatefulWidget {
  const ScanServerQrScreen({super.key});

  @override
  State<ScanServerQrScreen> createState() => _ScanServerQrScreenState();
}

class _ScanServerQrScreenState extends State<ScanServerQrScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (code == null || code.trim().isEmpty) return;
    _handled = true;
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.scanOfficeQr)),
      body: Column(
        children: [
          Expanded(child: MobileScanner(onDetect: _onDetect)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: const SafeArea(
              top: false,
              child: Text(
                S.scanOfficeQrHelp,
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
