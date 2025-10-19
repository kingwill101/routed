import 'package:collection/collection.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;

import 'provider.dart';

const Set<String> _defaultTruthy = {'true', '1', 'yes', 'on'};
const Set<String> _defaultFalsy = {'false', '0', 'off', 'no'};

/// Represents a configuration node that should be merged into a combined map.
class ConfigMapCandidate {
  const ConfigMapCandidate(this.value, {required this.context, this.transform});

  /// Convenience for pulling a candidate directly from [config] using [path].
  factory ConfigMapCandidate.fromConfig(
    Config config,
    String path, {
    Map<String, dynamic> Function(Object value)? transform,
  }) {
    return ConfigMapCandidate(
      config.get(path),
      context: path,
      transform: transform,
    );
  }

  /// Underlying value. Null values are ignored when merging.
  final Object? value;

  /// Human-readable context used when reporting configuration errors.
  final String context;

  /// Optional custom mapper that can turn non-Map values into a map before
  /// merging (e.g. converting strongly typed config objects).
  final Map<String, dynamic> Function(Object value)? transform;
}

/// Merges a sequence of [ConfigMapCandidate]s into a single map, applying each
/// candidate in order. Later candidates overwrite earlier keys.
Map<String, dynamic> mergeConfigCandidates(
  Iterable<ConfigMapCandidate> candidates, {
  bool dropNulls = false,
}) {
  final result = <String, dynamic>{};
  for (final candidate in candidates) {
    final value = candidate.value;
    if (value == null) {
      continue;
    }
    final fragment = candidate.transform != null
        ? candidate.transform!(value)
        : stringKeyedMap(value, candidate.context);
    fragment.forEach((key, entry) {
      if (dropNulls && entry == null) {
        return;
      }
      result[key] = entry;
    });
  }
  return result;
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
  if (value is Config) {
    return Map<String, dynamic>.from(value.all());
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

/// Parses [value] into an integer, accepting numeric strings.
int? parseIntLike(
  Object? value, {
  required String context,
  bool nonNegative = false,
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
    collected.addAll(
      value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty),
    );
  } else {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a string or list');
    }
    return null;
  }
  if (collected.isEmpty && !allowEmptyResult) {
    return null;
  }
  return collected;
}

/// Parses [value] into a [Duration]. Strings may use `ms`, `s`, `m`, or `h`
/// suffixes. Numeric values are treated as seconds.
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
      r'^(?<amount>-?\d+(?:\.\d+)?)(?<unit>ms|s|m|h|d|w|mo|y)?$',
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
    final milliseconds = switch (unit) {
      'ms' => amount,
      's' => amount * 1000,
      'm' => amount * 60 * 1000,
      'h' => amount * 60 * 60 * 1000,
      'd' => amount * 24 * 60 * 60 * 1000,
      'w' => amount * 7 * 24 * 60 * 60 * 1000,
      'mo' => amount * 30 * 24 * 60 * 60 * 1000,
      'y' => amount * 365 * 24 * 60 * 60 * 1000,
      _ => amount * 1000,
    };
    return Duration(milliseconds: milliseconds.round());
  }
  if (throwOnInvalid) {
    throw ProviderConfigException('$context must be a duration');
  }
  return null;
}

/// Parses [value] into a set of strings. Returns null when the underlying list
/// is empty and [allowEmptyResult] is false.
Set<String>? parseStringSet(
  Object? value, {
  required String context,
  bool allowEmptyResult = false,
  bool toLowerCase = false,
  bool coerceNonStringEntries = false,
  bool throwOnInvalid = true,
}) {
  final list = parseStringList(
    value,
    context: context,
    allowEmptyResult: allowEmptyResult,
    coerceNonStringEntries: coerceNonStringEntries,
    throwOnInvalid: throwOnInvalid,
  );
  if (list == null) {
    return null;
  }
  return list.map((entry) => toLowerCase ? entry.toLowerCase() : entry).toSet();
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

/// Helper for comparing order-agnostic lists in providers.
const ListEquality<String> stringListEquality = ListEquality<String>();
