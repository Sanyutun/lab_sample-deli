import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../../data/services/tracking_service.dart';
import '../../data/storage/location_queue.dart';
import '../widgets/state_views.dart';

/// Tells the delivery man that location sharing is running and lists the fixes
/// captured on this phone, marking which ones the office has received.
class LocationTab extends StatefulWidget {
  const LocationTab({super.key});

  @override
  State<LocationTab> createState() => _LocationTabState();
}

class _LocationTabState extends State<LocationTab> {
  List<QueuedFix>? _items;
  TrackingService? _tracking;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final tracking = AppScope.of(context).tracking;
    _tracking = tracking;
    tracking.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _tracking?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final queue = AppScope.of(context).queue;
    queue.recent().then((items) {
      if (!mounted) return;
      setState(() => _items = items);
    });
  }

  Future<void> _sendNow() async {
    setState(() => _busy = true);
    await _tracking!.syncNow();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _tracking!;
    return Column(
      children: [
        _status(tracking),
        Expanded(child: _history(tracking)),
      ],
    );
  }

  Widget _status(TrackingService tracking) {
    final on = tracking.streaming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        color: (on ? Colors.teal : Colors.orange).shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    on ? Icons.location_on : Icons.location_off,
                    color: on ? Colors.teal : Colors.deepOrange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    on ? S.locationOn : S.locationOff,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                on
                    ? S.locationOnNote(fmtMinutes(tracking.interval))
                    : S.locationOffNote,
                style: const TextStyle(fontSize: 12),
              ),
              if (on && tracking.batteryOptimized) ...[
                const SizedBox(height: 6),
                const Text(
                  S.batteryWarning,
                  style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                ),
                TextButton(
                  onPressed: () => AppScope.of(
                    context,
                  ).location.requestIgnoreBatteryOptimization(),
                  child: const Text(S.allowBackground),
                ),
              ],
              if (tracking.note != null) ...[
                const SizedBox(height: 8),
                Text(
                  tracking.note!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => AppScope.of(
                        context,
                      ).location.openAppSettings(),
                      child: const Text(S.openSettings),
                    ),
                    TextButton(
                      onPressed: () => tracking.retry(),
                      child: const Text(S.tryAgain),
                    ),
                  ],
                ),
              ],
              if (tracking.lastSentAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  S.lastSent(
                    fmtDateTime(tracking.lastSentAt!.millisecondsSinceEpoch),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tracking.pending == 0
                          ? S.allFixesSent(fmtMinutes(tracking.retention))
                          : S.fixesWaiting(tracking.pending),
                      style: TextStyle(
                        fontSize: 12,
                        color: tracking.pending == 0
                            ? Colors.teal.shade800
                            : Colors.deepOrange,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _sendNow,
                    child: const Text(S.sendNow),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _history(TrackingService tracking) {
    final items = _items;
    if (items == null) return const LoadingView();
    if (items.isEmpty) {
      return const EmptyView(
        message: S.noLocationsYet,
        icon: Icons.place_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await tracking.syncNow();
        _reload();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final g = items[i];
          final sent = g.transferred;
          return Card(
            child: ListTile(
              leading: Icon(
                sent ? Icons.cloud_done : Icons.cloud_upload_outlined,
                color: sent ? Colors.teal : Colors.deepOrange,
              ),
              title: Text(
                '${g.latitude.toStringAsFixed(5)}, '
                '${g.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${fmtDateTime(g.capturedAt)}\n${accuracyLabel(g.accuracyM)}',
              ),
              isThreeLine: true,
              trailing: Chip(
                label: Text(
                  sent ? S.sent : S.waiting,
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: sent
                    ? Colors.teal.shade100
                    : Colors.orange.shade100,
              ),
            ),
          );
        },
      ),
    );
  }
}
