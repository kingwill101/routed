/// Selects a pluralized message branch from a compact message string.
///
/// The selector supports the common `singular|plural` form and inline exact or
/// range conditions such as `{0} None|{1} One|[2,*] Many`:
///
/// ```dart
/// final selector = MessageSelector();
/// selector.choose('{0} No files|{1} One file|[2,*] :count files', 3, 'en');
/// // ':count files'
/// ```
///
/// The built-in implementation uses an English-like rule for an unconditioned
/// message: exactly `1` selects the first branch and every other number selects
/// the last branch. The `locale` argument is accepted for the translator
/// contract but is not currently used to apply locale-specific plural rules.
class MessageSelector {
  /// Picks the branch in [line] that matches [number].
  ///
  /// Conditions use `{n}` for an exact number and `[lower,upper]` for an
  /// inclusive range. Either range bound may be `*`. Branch text is trimmed;
  /// Placeholder replacement is performed by `Translator` after selection.
  ///
  /// [locale] identifies the locale being translated, but the built-in
  /// selector currently uses the same English-like rule for every locale.
  String choose(String line, num number, String locale) {
    final segments = line.split('|');
    final conditioned = _extractCondition(segments, number);
    if (conditioned != null) {
      return conditioned.trim();
    }
    if (segments.length == 1) {
      return segments.first.trim();
    }

    // Default to English-like pluralisation rules for now. Additional locale
    // aware behaviour can piggyback on Intl plural rules later.
    if (number == 1) {
      return segments.first.trim();
    }
    return segments.last.trim();
  }

  String? _extractCondition(List<String> segments, num number) {
    final pattern = RegExp(r'^[\{\[]([^\[\]\{\}]*)[\}\]]');
    for (final part in segments) {
      final match = pattern.firstMatch(part);
      if (match == null) {
        continue;
      }
      final condition = match.group(1)!;
      final remainder = part.substring(match.end).trim();
      if (_matchesCondition(condition, number)) {
        return remainder;
      }
    }
    return null;
  }

  bool _matchesCondition(String condition, num number) {
    if (condition.contains(',')) {
      final pieces = condition.split(',');
      if (pieces.length != 2) {
        return false;
      }
      final lowerRaw = pieces.first.trim();
      final upperRaw = pieces.last.trim();
      final lower = lowerRaw == '*' ? null : num.tryParse(lowerRaw);
      final upper = upperRaw == '*' ? null : num.tryParse(upperRaw);
      final lowerOk = lower == null || number >= lower;
      final upperOk = upper == null || number <= upper;
      return lowerOk && upperOk;
    }
    final exact = num.tryParse(condition.trim());
    return exact != null && exact == number;
  }
}
