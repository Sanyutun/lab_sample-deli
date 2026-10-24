/// Phone-number matching for call logging. Each side holds the number in its
/// own written form — `09771234567`, `+95 9 77 1234 567`, `95977…` — so both
/// sides are reduced to digits and the country/trunk prefixes dropped before
/// comparing. Covers Myanmar mobiles; landlines with a short national format
/// do not match and would need their own rule.
String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp('[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  // The country code is written without a trunk zero, which makes those
  // numbers at least 11 digits — a local 10-digit mobile can then never be
  // mistaken for one and wrongly stripped.
  if (digits.length >= 11 && digits.startsWith('95')) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  return digits;
}

/// True when [a] and [b] are the same number written two ways. Empty or
/// unreadable numbers (private callers, `unknown`) never match anything.
bool samePhone(String a, String b) {
  final na = normalizePhone(a);
  final nb = normalizePhone(b);
  return na.isNotEmpty && na == nb;
}
