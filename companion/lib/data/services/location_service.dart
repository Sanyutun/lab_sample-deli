import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/failure.dart';
import '../../core/strings.dart';

enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// A single GPS fix. [accuracyM] is null when the device did not report one —
/// the UI must not invent an accuracy figure.
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyM,
  });

  final double latitude;
  final double longitude;
  final int capturedAt;
  final double? accuracyM;
}

/// Thin wrapper over the GPS so screens and tests do not depend on the plugin
/// directly. While the delivery man is signed in the app runs a foreground
/// service (the ongoing notification) and streams fixes; that service is how
/// Android lets a backgrounded app keep receiving location.
abstract class LocationService {
  Future<LocationAccess> requestAccess();

  Future<Fix> currentFix();

  /// Continuous fixes while the app is signed in, one every [interval]. The
  /// plugin raises a foreground service for the duration of the subscription.
  Stream<Fix> positionStream(Duration interval);

  /// Opens the system settings page for this app, so the user can grant the
  /// "Allow all the time" location permission Android 11+ no longer offers in
  /// the in-app dialog.
  Future<void> openAppSettings();

  /// Whether Android is allowed to kill this app's background work for battery.
  /// True also means "could not tell", so the UI never nags without evidence.
  Future<bool> isBatteryOptimizationIgnored();

  /// Asks Android to stop optimising this app's battery use. On some devices
  /// this opens a system dialog; on others it opens the settings list.
  Future<void> requestIgnoreBatteryOptimization();

  /// Asks for permission to show the ongoing notification that tells the user
  /// location sharing is running. Best effort: the app still reports tracking
  /// state in its own Location tab if this is refused.
  Future<void> requestNotificationPermission();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  @override
  Future<Fix> currentFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return _toFix(position);
    } on TimeoutException {
      throw const LocationFailure(S.gpsTimeout);
    } on LocationServiceDisabledException {
      throw const LocationFailure(S.locationServicesOff);
    }
  }

  @override
  Stream<Fix> positionStream(Duration interval) {
    // The interval comes from the office GPS policy. No distance filter: a man
    // standing still at a delivery still has to appear on the route, and a
    // missing point must mean "the phone did not report", never "he did not
    // move".
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: interval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: S.notifTitle,
        notificationText: S.notifText,
        notificationChannelName: S.notifChannel,
        setOngoing: true,
        enableWakeLock: true,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(_toFix);
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  static const MethodChannel _notifications = MethodChannel(
    'lab_delivery_companion/notifications',
  );

  @override
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      return await _notifications.invokeMethod<bool>('batteryIgnored') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> requestIgnoreBatteryOptimization() async {
    try {
      await _notifications.invokeMethod<void>('requestIgnoreBattery');
    } on MissingPluginException {
      await openAppSettings();
    } on PlatformException {
      await openAppSettings();
    }
  }

  @override
  Future<void> requestNotificationPermission() async {
    try {
      await _notifications.invokeMethod<void>('request');
    } on MissingPluginException {
      // No native handler (nothing asked for on a non-Android host).
    } on PlatformException {
      // Best effort; the Location tab reports the state either way.
    }
  }

  static Fix _toFix(Position p) => Fix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracyM: p.accuracy,
    capturedAt: p.timestamp.millisecondsSinceEpoch,
  );
}
