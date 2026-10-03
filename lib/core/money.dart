class MoneyParser {
  const MoneyParser._();

  static int? parseCnyMinor(String input) {
    final normalized = input.trim();
    final match = RegExp(r'^(?:0|[1-9]\d*)(?:\.(\d{1,2}))?$')
        .firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(normalized.split('.').first);
    if (whole == null) return null;
    final fraction = match.group(1) ?? '';
    final fractionMinor = switch (fraction.length) {
      0 => 0,
      1 => int.parse(fraction) * 10,
      _ => int.parse(fraction),
    };
    final amount = whole * 100 + fractionMinor;
    return amount > 0 ? amount : null;
  }

  static String formatCnyMinor(int amountMinor) {
    final whole = amountMinor ~/ 100;
    final fraction = (amountMinor % 100).toString().padLeft(2, '0');
    return '¥$whole.$fraction';
  }

  static String editableCny(int amountMinor) {
    final whole = amountMinor ~/ 100;
    final fraction = amountMinor % 100;
    return fraction == 0
        ? whole.toString()
        : '$whole.${fraction.toString().padLeft(2, '0')}';
  }
}
