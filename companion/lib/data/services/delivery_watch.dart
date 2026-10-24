import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../repositories/companion_repository.dart';

/// One delivery the office has recorded for this man.
class NewDelivery {
  const NewDelivery({
    required this.number,
    required this.commission,
    required this.recordedAt,
    required this.paid,
  });

  /// The board position, which is stable for a given delivery.
  final int number;
  final int commission;
  final int? recordedAt;
  final bool paid;

  String get amountLabel => fmtMMK(commission);
  String get whenLabel =>
      recordedAt == null ? S.dash : fmtDateTime(recordedAt!);
  String get statusLabel => paid ? S.badgePaid : S.badgeUnpaid;
}

/// A tiny key-value store, so the watch can be tested without the platform.
abstract class SeenKvStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Watches the delivery board and reports deliveries that were not there last
/// time.
///
/// It cannot interrupt while the app is closed — this phone has no push
/// channel, and the app is read-only — so it reports on each refresh instead.
/// That limit is reported honestly rather than hidden.
class DeliveryWatch extends ChangeNotifier {
  DeliveryWatch({
    required this.repository,
    required this.store,
    this.key = 'deliveryWatch',
  });

  final CompanionRepository repository;
  final SeenKvStore store;
  final String key;

  /// Deliveries found since the man last dismissed the alert.
  final List<NewDelivery> _pending = [];
  List<NewDelivery> get pending => List.unmodifiable(_pending);

  bool _checking = false;
  bool get checking => _checking;

  /// Fetches the board and reports what is new.
  ///
  /// The *first* successful read only records what already exists: otherwise a
  /// fresh install would announce every past delivery at once. After that, a
  /// position that turns up in a settled state is announced once.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      await observe((await repository.deliveryBoard()).value);
    } on AppFailure {
      // Offline or signed out: keep whatever is already pending and try again
      // on the next tick. Never invent a delivery from a failed read.
    } finally {
      _checking = false;
    }
  }

  /// Reports what is new in a board that was fetched elsewhere — the board
  /// screen's pull-to-refresh, for example. Sharing this path means a refresh
  /// announces exactly what the polling would have.
  Future<void> observe(DeliveryBoardDto board) async {
    final slots = _recordedSlots(board);
    final previous = await _readSeen();
    if (previous != null) {
      final fresh = [
        for (final entry in slots.entries)
          if (previous[entry.key] != entry.value) entry.key,
      ];
      final added = _pending.map((d) => 'slot.${d.number}').toSet();
      _pending.addAll([
        for (final number in fresh)
          if (!added.contains(number)) _describe(board, number),
      ]);
      if (_pending.isNotEmpty) notifyListeners();
    }
    await _writeSeen(slots);
  }

  /// Clears the alert once the man has seen it. What was seen stays recorded,
  /// so the same delivery is not announced twice.
  void clear() {
    if (_pending.isEmpty) return;
    _pending.clear();
    notifyListeners();
  }

  /// Forgets everything, so the next man on this phone starts from a clean
  /// baseline instead of being told about the previous man's deliveries.
  Future<void> reset() async {
    _pending.clear();
    await store.write(key, '');
    notifyListeners();
  }

  /// Every position that holds a real delivery, with the state that decides
  /// whether it is worth reporting.
  Map<String, String> _recordedSlots(DeliveryBoardDto board) => {
    for (final group in board.groups)
      for (final slot in group.slots)
        if (slot.state == 'successful' || slot.state == 'pending')
          'slot.${slot.number}':
              '${slot.state}:${slot.paid}:${slot.commission}',
  };

  NewDelivery _describe(DeliveryBoardDto board, String key) {
    final number = int.parse(key.substring('slot.'.length));
    for (final group in board.groups) {
      for (final slot in group.slots) {
        if (slot.number != number) continue;
        return NewDelivery(
          number: slot.number,
          commission: slot.commission,
          recordedAt: slot.recordedAt,
          paid: slot.paid,
        );
      }
    }
    // Unreachable: the key came from this same board. Kept honest.
    return NewDelivery(
      number: number,
      commission: 0,
      recordedAt: null,
      paid: false,
    );
  }

  Future<Map<String, String>?> _readSeen() async {
    final raw = await store.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry('$k', '$v'));
    } on FormatException {
      return null; // A corrupt value must not stop the board from working.
    }
  }

  Future<void> _writeSeen(Map<String, String> slots) =>
      store.write(key, jsonEncode(slots));
}
