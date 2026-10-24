import 'dart:math';

final _rng = Random();

String newId(String prefix) {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = _rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
  return '${prefix}_${ts}_$rand';
}

String todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;
