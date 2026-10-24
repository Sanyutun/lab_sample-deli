import 'dart:io';

import 'package:flutter/services.dart';

/// The Android phone: the stream of calls that rang the lab, plus the runtime
/// permission the calling number needs. Both platform channels only exist on
/// Android — every other platform answers as "permission granted, nothing to
/// report", so Windows and tests never touch a channel.
class IncomingCalls {
  static const EventChannel _events = EventChannel('lab.calls/events');
  static const MethodChannel _permissions = MethodChannel(
    'lab.calls/permissions',
  );

  /// One event per ended call: `number` (String?, null when Android hides
  /// it), `at` (int — ms when it started ringing) and `answered` (bool; false
  /// means the ring was never picked up).
  static Stream<Map<String, Object?>> get events =>
      _events
          .receiveBroadcastStream()
          .map((e) => Map<String, Object?>.from(e as Map));

  static Future<bool> hasPermission() => _ask('has');

  /// Shows the Android permission dialog; safe to call on every app start
  /// (Android only asks once).
  static Future<bool> requestPermission() => _ask('request');

  static Future<bool> _ask(String method) async {
    if (!Platform.isAndroid) return true;
    try {
      return await _permissions.invokeMethod<bool>(method) ?? false;
    } on Exception {
      return false;
    }
  }
}
