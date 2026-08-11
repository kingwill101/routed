/// Minimal pluralization helper modelled after Laravel's MessageSelector.
///
/// It supports the most common `singular|plural` syntax along with optional
/// inline conditions such as `{0} None|{1} One|[2,*] Many`.
class MessageSelector {
  /// Picks the appropriate segment from [line] based on [number].
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
