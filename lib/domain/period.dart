// Date helpers for day/month reporting periods. All dates use the ISO
// `yyyy-MM-dd` form and months use `yyyy-MM`, so plain string comparison is
// chronological.

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String isoDateOf(int ms) => formatIso(DateTime.fromMillisecondsSinceEpoch(ms));

String monthOfIso(String iso) => iso.length >= 7 ? iso.substring(0, 7) : iso;

String monthFirstDay(String month) => '$month-01';

String monthLastDay(String month) {
  final parts = month.split('-');
  final year = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final last = DateTime(year, m + 1, 0).day;
  return '$month-${last.toString().padLeft(2, '0')}';
}

String dayBefore(String iso) =>
    formatIso(DateTime.parse(iso).subtract(const Duration(days: 1)));

/// True when [date] falls within [from]..[to] (both inclusive, ISO strings).
bool withinRange(String date, String from, String to) =>
    from.compareTo(date) <= 0 && date.compareTo(to) <= 0;

String monthLabel(String month) {
  final parts = month.split('-');
  final m = int.parse(parts[1]);
  return '${_monthNames[m - 1]} ${parts[0]}';
}

String monthName(int month) => _monthNames[month - 1];
