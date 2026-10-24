import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/failure.dart';
import '../../core/strings.dart';
import '../repositories/companion_repository.dart';
import '../storage/location_queue.dart';
import 'location_service.dart';

/// Runs the background location stream while a delivery man is signed in,
/// stores every fix on the phone, and pushes the backlog to the office whenever
/// the server is reachable. Fixes the office has acknowledged are flagged
/// transferred so they are never sent twice.
class TrackingService extends ChangeNotifier {
  TrackingService({
    required this.location,
    required this.queue,
    required this.repository,
    this.syncInterval = const Duration(seconds: 30),
  });

  final LocationService location;
  final LocationQueue queue;
  final CompanionRepository repository;
  final Duration syncInterval;

  /// How often a fix is captured and how long a *sent* fix stays on the phone.
  /// Both come from the office GPS policy; until the first fetch succeeds they
  /// are the standard values. Unsent fixes are never dropped by retention.
  Duration _interval = GpsPolicyDto.standard.interval;
  Duration _retention = GpsPolicyDto.standard.retention;

  Duration get interval => _interval;
  Duration get retention => _retention;

  final Random _random = Random();

  StreamSubscription<Fix>? _subscription;
  Timer? _retry;
  bool _signedIn = false;
  bool _streaming = false;
  LocationAccess? _access;
  int _pending = 0;
  DateTime? _lastSentAt;
  String? _note;

  /// True while the man is signed in and tracking should be running.
  bool get signedIn => _signedIn;

  /// True when fixes are actually arriving from the GPS.
  bool get streaming => _streaming;

  LocationAccess? get access => _access;

  /// Fixes captured but not yet acknowledged by the office.
  int get pending => _pending;

  DateTime? get lastSentAt => _lastSentAt;

  /// A plain-language reason tracking is not running, if any.
  String? get note => _note;

  /// True when Android is allowed to kill background tracking to save battery.
  /// Starts false (nothing known yet) so the UI does not nag before it checked.
  bool get batteryOptimized => _batteryOptimized;

  bool _batteryOptimized = false;

  /// Called whenever sign-in state changes. Starts the stream on sign-in and
  /// stops it — discarding the backlog — on sign-out, so one man's fixes are
  /// never filed against the next man who signs in on this phone.
  Future<void> onSignedInChanged(bool signedIn) async {
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      await _start();
    } else {
      _stop();
      await queue.clear();
      _pending = 0;
      _access = null;
      _note = null;
      _lastSentAt = null;
    }
    notifyListeners();
  }

  Future<void> _start() async {
    _note = null;
    await _loadPolicy();
    final access = await location.requestAccess();
    _access = access;
    if (access != LocationAccess.granted) {
      _streaming = false;
      _note = switch (access) {
        LocationAccess.serviceDisabled => S.trackServiceOff,
        LocationAccess.denied => S.trackDenied,
        LocationAccess.deniedForever => S.trackBlocked,
        LocationAccess.granted => null,
      };
      notifyListeners();
      return;
    }

    // The ongoing notification is how the man sees that tracking is on;
    // Android 13+ hides it from the drawer until notification permission is
    // granted, which geolocator does not ask for itself.
    await location.requestNotificationPermission();
    _batteryOptimized = !(await location.isBatteryOptimizationIgnored());

    _subscription?.cancel();
    _subscription = location
        .positionStream(_interval)
        .listen(
          (fix) => unawaited(_onFix(fix)),
          onError: (Object e) {
            _streaming = false;
            _note = e is AppFailure ? e.message : S.trackStopped;
            notifyListeners();
          },
        );
    _streaming = true;
    _retry ??= Timer.periodic(syncInterval, (_) => unawaited(syncNow()));
    _pending = await queue.countPending();
    notifyListeners();
    await syncNow();
  }

  /// Re-checks permission and restarts the stream. Used after the user returns
  /// from Android settings having changed the location permission.
  Future<void> retry() async {
    if (!_signedIn) return;
    await _start();
    notifyListeners();
  }

  /// Stops the stream. Cancelling is fire-and-forget: the subscription stops
  /// delivering at once, and nothing here needs to wait for the plugin.
  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _retry?.cancel();
    _retry = null;
    _streaming = false;
  }

  Future<void> _onFix(Fix fix) async {
    try {
      await queue.add(
        QueuedFix(
          id: _newClientId(),
          latitude: fix.latitude,
          longitude: fix.longitude,
          capturedAt: fix.capturedAt,
          accuracyM: fix.accuracyM,
        ),
      );
      _pending = await queue.countPending();
      notifyListeners();
      await syncNow();
    } on AppFailure catch (e) {
      _note = e.message;
      notifyListeners();
    }
  }

  /// Sends every unsent fix, oldest first. Stops at the first connection
  /// problem and leaves the rest queued for the next attempt.
  Future<void> syncNow() async {
    final backlog = await queue.pending();
    if (backlog.isEmpty) {
      _pending = 0;
      await _dropExpired();
      return;
    }
    final sent = <String>[];
    for (final fix in backlog) {
      try {
        await repository.recordLocation(
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyM: fix.accuracyM,
          capturedAt: fix.capturedAt,
          clientId: fix.id,
        );
        sent.add(fix.id);
      } on AppFailure {
        // Offline, or the session is gone: retrying the rest now is pointless.
        break;
      }
    }
    if (sent.isNotEmpty) {
      // Marked sent only after the office confirmed each one; a fix is never
      // dropped for failing to upload.
      await queue.markTransferred(sent);
      _lastSentAt = DateTime.now();
      _note = null;
    }
    await _dropExpired();
    _pending = await queue.countPending();
    notifyListeners();
  }

  /// Applies the rolling window: fixes the office already has, older than
  /// [_retention], are deleted. Pending fixes stay until they are sent.
  Future<void> _dropExpired() async {
    final cutoff = DateTime.now().subtract(_retention).millisecondsSinceEpoch;
    final dropped = await queue.purgeTransferredBefore(cutoff);
    if (dropped > 0) _pending = await queue.countPending();
  }

  /// Fetches the office GPS policy. Best effort: offline, the last policy this
  /// phone saw (or the standard values on first run) stays in force.
  Future<void> _loadPolicy() async {
    try {
      final policy = await repository.gpsPolicy();
      _interval = policy.value.interval;
      _retention = policy.value.retention;
    } on AppFailure {
      // Keep what we already have.
    }
  }

  String _newClientId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'c$micros-${_random.nextInt(1 << 31)}';
  }
}
