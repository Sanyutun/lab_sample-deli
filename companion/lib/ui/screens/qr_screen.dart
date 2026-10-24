// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/state_views.dart';

/// The delivery man's personal identity code. The office scans this to pick the
/// correct person when assigning a receipt.
///
/// The payload is opaque and holds no money or personal data, and the office
/// always re-checks it against its own records before trusting it. Opening or
/// refreshing this screen asks the server for a new code, which invalidates the
/// previous one.
class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  QrIdentityDto? _qr;
  bool _loading = true;
  bool _stale = false;
  DateTime? _cachedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppScope.of(context).repository.qr();
      if (!mounted) return;
      setState(() {
        _qr = result.value;
        _stale = result.stale;
        _cachedAt = result.cachedAt;
        _loading = false;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).auth.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.myQrTitle),
        actions: [
          IconButton(
            tooltip: S.newCode,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(profile),
    );
  }

  Widget _body(DeliveryManProfileDto? profile) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final qr = _qr!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_stale) ...[
            OfflineBanner(cachedAt: _cachedAt),
            const SizedBox(height: 12),
          ],
          Text(
            profile?.name ?? S.dash,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            S.idLine(profile?.id ?? S.dash),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  QrImageView(
                    data: qr.payload,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.showToStaff,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.issuedAt(fmtDateTime(qr.issuedAt)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_stale)
            const _Note(
              icon: Icons.warning_amber,
              color: Colors.deepOrange,
              text: S.qrOfflineNote,
            )
          else
            const _Note(
              icon: Icons.info_outline,
              color: Colors.teal,
              text: S.qrInfoNote,
            ),
          const _Note(
            icon: Icons.autorenew,
            color: Colors.blueGrey,
            text: S.qrRotateNote,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text(S.getNewCode),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
