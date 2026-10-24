import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/strings.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text(S.tryAgain),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Shown when figures came from the on-device cache because the office server
/// could not be reached. Keeps the app honest about freshness.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.cachedAt});

  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Colors.orange.shade100,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.cloud_off, size: 18, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            cachedAt == null
                ? S.offlineNoData
                : S.offlineSince(
                    fmtDateTime(cachedAt!.millisecondsSinceEpoch),
                  ),
            style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
