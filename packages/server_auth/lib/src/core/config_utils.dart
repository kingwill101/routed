const Set<String> _defaultTruthy = {'true', '1', 'yes', 'on'};
const Set<String> _defaultFalsy = {'false', '0', 'off', 'no'};

/// Thrown when a provider receives invalid configuration.
class ProviderConfigException implements Exception {
  ProviderConfigException(this.message);

  final String message;

  @override
  String toString() => 'ProviderConfigException: $message';
}

/// Converts [value] into a string-keyed map, validating it is map-like.
Map<String, dynamic> stringKeyedMap(Object value, String context) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    final copy = <String, dynamic>{};
    value.forEach((key, dynamic entry) {
      copy[key.toString()] = entry;
    });
    return copy;
  }
  throw ProviderConfigException('$context must be a map');
}

/// Parses [value] into a boolean, supporting common string/number variants.
bool? parseBoolLike(
  Object? value, {
  required String context,
  bool allowNumeric = true,
  Map<String, bool>? stringMappings,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is num && allowNumeric) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    final mappings = stringMappings;
    if (mappings != null) {
      if (mappings.containsKey(normalized)) {
        return mappings[normalized]!;
      }
    } else {
      if (_defaultTruthy.contains(normalized)) {
        return true;
      }
      if (_defaultFalsy.contains(normalized)) {
        return false;
      }
    }
  }
  if (throwOnInvalid) {
    throw ProviderConfigException('$context must be a boolean');
  }
  return null;
}

/// Parses [value] as a string, optionally allowing empty values.
String? parseStringLike(
  Object? value, {
  required String context,
  bool allowEmpty = false,
  bool coerceNonString = false,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  String candidate;
  if (value is String) {
    candidate = value;
  } else if (coerceNonString) {
    candidate = value.toString();
  } else {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a string');
    }
    return null;
  }
  final trimmed = candidate.trim();
  if (!allowEmpty && trimmed.isEmpty) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a string');
    }
    return null;
  }
  return trimmed;
}

/// Parses [value] into a list of non-empty strings.
List<String>? parseStringList(
  Object? value, {
  required String context,
  bool allowEmptyResult = false,
  bool allowCommaSeparated = true,
  bool coerceNonStringEntries = false,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }

  final collected = <String>[];
  if (value is Iterable) {
    var index = 0;
    for (final entry in value) {
      if (entry == null) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context[$index] must be a string');
        }
        return null;
      }
      final normalized = parseStringLike(
        entry,
        context: '$context[$index]',
        coerceNonString: coerceNonStringEntries,
        throwOnInvalid: throwOnInvalid,
      );
      if (normalized == null || normalized.isEmpty) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context[$index] must be a string');
        }
        return null;
      }
      collected.add(normalized);
      index++;
    }
  } else if (value is String && allowCommaSeparated) {
    final parts = value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    collected.addAll(parts);
  } else {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a string or list');
    }
    return null;
  }

  if (!allowEmptyResult && collected.isEmpty) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must not be empty');
    }
    return null;
  }

  return collected;
}

/// Parses [value] into an integer, accepting numeric strings.
int? parseIntLike(
  Object? value, {
  required String context,
  bool nonNegative = false,
  bool allowEmpty = true,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  int? parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.toInt();
  } else if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (!allowEmpty) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context must be an integer');
        }
        return null;
      }
      return null;
    }
    parsed = int.tryParse(trimmed);
  }
  if (parsed == null) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be an integer');
    }
    return null;
  }
  if (nonNegative && parsed < 0) {
    throw ProviderConfigException('$context must be zero or positive');
  }
  return parsed;
}

/// Parses [value] into a [Duration]. Strings may use `ms`, `s`, `m`, `h`, `d`,
/// `w`, `mo`, and `y` suffixes. Numeric values are treated as seconds.
Duration? parseDurationLike(
  Object? value, {
  required String context,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  if (value is Duration) {
    return value;
  }
  if (value is num) {
    return Duration(milliseconds: (value * 1000).round());
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(
      r'^(?<amount>-?\d+(?:\.\d+)?)(?<unit>ms|s|m|h|d|day|days|w|week|weeks|mo|month|months|y|year|years)?$',
    ).firstMatch(trimmed);
    if (match == null) {
      if (throwOnInvalid) {
        throw ProviderConfigException('$context must be a duration');
      }
      return null;
    }
    final amountStr = match.namedGroup('amount')!;
    final unit = match.namedGroup('unit') ?? 's';
    final amount = double.tryParse(amountStr);
    if (amount == null) {
      if (throwOnInvalid) {
        throw ProviderConfigException('$context must be a duration');
      }
      return null;
    }
    const dayMs = 24 * 60 * 60 * 1000;
    final milliseconds = switch (unit) {
      'ms' => amount,
      's' => amount * 1000,
      'm' => amount * 60 * 1000,
      'h' => amount * 60 * 60 * 1000,
      'd' || 'day' || 'days' => amount * dayMs,
      'w' || 'week' || 'weeks' => amount * dayMs * 7,
      'mo' || 'month' || 'months' => amount * dayMs * 30,
      'y' || 'year' || 'years' => amount * dayMs * 365,
      _ => amount * 1000,
    };
    return Duration(milliseconds: milliseconds.round());
  }
  if (throwOnInvalid) {
    throw ProviderConfigException('$context must be a duration');
  }
  return null;
}

/// Coerces [value] into a string map, validating entries eagerly.
Map<String, String> parseStringMap(
  Object value, {
  required String context,
  bool allowEmptyValues = false,
  bool coerceValues = false,
}) {
  if (value is! Map) {
    throw ProviderConfigException('$context must be a map');
  }
  final result = <String, String>{};
  value.forEach((key, dynamic raw) {
    final entryKey = key.toString();
    String? normalized;
    if (raw is String) {
      normalized = raw.trim();
    } else if (coerceValues && raw != null) {
      normalized = raw.toString().trim();
    }
    if (normalized == null ||
        (normalized.isEmpty && !allowEmptyValues && raw != null)) {
      throw ProviderConfigException('$context.$entryKey must be a string');
    }
    result[entryKey] = normalized;
  });
  return result;
}

/// Coerces [value] into a string map, skipping null entries.
Map<String, String> parseStringMapAllowNulls(
  Object? value, {
  required String context,
  bool allowEmptyValues = false,
  bool coerceValues = false,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return const <String, String>{};
  }
  if (value is! Map) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a map');
    }
    return const <String, String>{};
  }
  final source = stringKeyedMap(value, context);
  final filtered = <String, dynamic>{};
  source.forEach((key, entry) {
    if (entry != null) {
      filtered[key] = entry;
    }
  });
  if (filtered.isEmpty) {
    return const <String, String>{};
  }
  return parseStringMap(
    filtered,
    context: context,
    allowEmptyValues: allowEmptyValues,
    coerceValues: coerceValues,
  );
}

/// Coerces [value] into a list of string-keyed maps.
List<Map<String, dynamic>> parseMapList(
  Object? value, {
  required String context,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return const <Map<String, dynamic>>[];
  }
  if (value is! Iterable) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a list');
    }
    return const <Map<String, dynamic>>[];
  }
  final result = <Map<String, dynamic>>[];
  var index = 0;
  for (final entry in value) {
    if (entry == null) {
      if (throwOnInvalid) {
        throw ProviderConfigException('$context[$index] must be a map');
      }
      return const <Map<String, dynamic>>[];
    }
    result.add(stringKeyedMap(entry as Object, '$context[$index]'));
    index += 1;
  }
  return result;
}
