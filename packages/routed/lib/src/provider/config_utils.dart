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

/// Parses [value] into a double, accepting numeric strings.
double? parseDoubleLike(
  Object? value, {
  required String context,
  bool allowEmpty = true,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  double? parsed;
  if (value is double) {
    parsed = value;
  } else if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (!allowEmpty) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context must be a number');
        }
        return null;
      }
      return null;
    }
    parsed = double.tryParse(trimmed);
  }
  if (parsed == null) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a number');
    }
    return null;
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

/// Parses [value] into a list of integers.
List<int>? parseIntList(
  Object? value, {
  required String context,
  bool allowEmptyResult = false,
  bool allowCommaSeparated = true,
  bool allowInvalidStringEntries = false,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  final collected = <int>[];
  if (value is Iterable) {
    var index = 0;
    for (final entry in value) {
      final parsed = parseIntLike(
        entry,
        context: '$context[$index]',
        throwOnInvalid: throwOnInvalid,
      );
      if (parsed == null) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context[$index] must be an integer');
        }
        return null;
      }
      collected.add(parsed);
      index += 1;
    }
  } else if (value is String && allowCommaSeparated) {
    final parts = value.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(trimmed);
      if (parsed == null) {
        if (allowInvalidStringEntries) {
          continue;
        }
        if (throwOnInvalid) {
          throw ProviderConfigException('$context must be a list of ints');
        }
        return null;
      }
      collected.add(parsed);
    }
  } else {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a list or string');
    }
    return null;
  }
  if (collected.isEmpty && !allowEmptyResult) {
    return null;
  }
  return collected;
}

/// Parses [value] into a list of doubles.
List<double>? parseDoubleList(
  Object? value, {
  required String context,
  bool allowEmptyResult = false,
  bool allowCommaSeparated = true,
  bool allowInvalidStringEntries = false,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return null;
  }
  final collected = <double>[];
  if (value is Iterable) {
    var index = 0;
    for (final entry in value) {
      double? parsed;
      if (entry is num) {
        parsed = entry.toDouble();
      } else if (entry is String) {
        parsed = double.tryParse(entry.trim());
      }
      if (parsed == null) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context[$index] must be a number');
        }
        return null;
      }
      collected.add(parsed);
      index += 1;
    }
  } else if (value is String && allowCommaSeparated) {
    final parts = value.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parsed = double.tryParse(trimmed);
      if (parsed == null) {
        if (allowInvalidStringEntries) {
          continue;
        }
        if (throwOnInvalid) {
          throw ProviderConfigException('$context must be a list of numbers');
        }
        return null;
      }
      collected.add(parsed);
    }
  } else {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a list or string');
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
  if (value is! Map && value is! Config) {
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

/// Coerces [value] into a map of string lists.
Map<String, List<String>> parseStringListMap(
  Object? value, {
  required String context,
  bool throwOnInvalid = true,
}) {
  if (value == null) {
    return {};
  }
  if (value is! Map) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a map');
    }
    return {};
  }
  final result = <String, List<String>>{};
  value.forEach((key, dynamic raw) {
    final entryKey = key.toString();
    final list = parseStringList(
      raw,
      context: '$context.$entryKey',
      throwOnInvalid: throwOnInvalid,
    );
    if (list != null) {
      result[entryKey] = list;
    }
  });
  return result;
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

/// Coerces [value] into a nested string-keyed map.
Map<String, Map<String, dynamic>> parseNestedMap(
  Object? value, {
  required String context,
  bool throwOnInvalid = true,
  bool allowNullEntries = true,
}) {
  if (value == null) {
    return <String, Map<String, dynamic>>{};
  }
  if (value is! Map && value is! Config) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a map');
    }
    return <String, Map<String, dynamic>>{};
  }
  final source = stringKeyedMap(value, context);
  final result = <String, Map<String, dynamic>>{};
  source.forEach((key, entry) {
    final entryKey = key.toString();
    if (entry == null) {
      if (!allowNullEntries) {
        if (throwOnInvalid) {
          throw ProviderConfigException('$context.$entryKey must be a map');
        }
        return;
      }
      result[entryKey] = <String, dynamic>{};
      return;
    }
    if (entry is! Map && entry is! Config) {
      if (throwOnInvalid) {
        throw ProviderConfigException('$context.$entryKey must be a map');
      }
      return;
    }
    result[entryKey] = stringKeyedMap(entry as Object, '$context.$entryKey');
  });
  return result;
}

/// Helper for comparing order-agnostic lists in providers.
const ListEquality<String> stringListEquality = ListEquality<String>();

extension ConfigHelpers on String {
  Duration? toDuration({bool throwOnInvalid = true}) => parseDurationLike(
    this,
    context: 'String',
    throwOnInvalid: throwOnInvalid,
  );
}

extension ConfigUtils on Config {
  /// Gets a boolean value from config, with automatic type conversion.
  ///
  /// Supports string values like 'true', 'false', '1', '0', 'yes', 'no', 'on', 'off'.
  /// Returns [defaultValue] if the key doesn't exist or can't be converted.
  bool getBool(
    String path, {
    bool defaultValue = false,
    Map<String, bool>? stringMappings,
  }) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return defaultValue;

      final parsed = parseBoolLike(
        rawValue,
        context: path,
        stringMappings: stringMappings ?? const {'true': true, 'false': false},
        throwOnInvalid: false,
      );
      return parsed ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets an optional boolean value from config, with automatic type conversion.
  ///
  /// Returns null if the key doesn't exist or can't be converted to a boolean.
  bool? getBoolOrNull(String path, {Map<String, bool>? stringMappings}) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return null;

      return parseBoolLike(
        rawValue,
        context: path,
        stringMappings: stringMappings ?? const {'true': true, 'false': false},
        throwOnInvalid: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Gets an integer value from config, with automatic type conversion.
  ///
  /// Supports numeric strings and returns [defaultValue] if conversion fails.
  int getInt(String path, {int defaultValue = 0}) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return defaultValue;

      final parsed = parseIntLike(
        rawValue,
        context: path,
        throwOnInvalid: false,
      );
      return parsed ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets an optional integer value from config.
  ///
  /// Returns null if the key doesn't exist or can't be converted to an integer.
  int? getIntOrNull(String path) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return null;

      return parseIntLike(rawValue, context: path, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a string value from config, with optional empty string handling.
  ///
  /// Returns [defaultValue] if the key doesn't exist.
  /// If [allowEmpty] is false, returns [defaultValue] for empty/whitespace strings.
  String getString(
    String path, {
    String defaultValue = '',
    bool allowEmpty = true,
  }) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return defaultValue;

      final parsed = parseStringLike(
        rawValue,
        context: path,
        allowEmpty: allowEmpty,
        throwOnInvalid: false,
      );
      return parsed ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets an optional string value from config.
  ///
  /// Returns null if the key doesn't exist.
  /// If [allowEmpty] is false, returns null for empty/whitespace strings.
  String? getStringOrNull(String path, {bool allowEmpty = true}) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return null;

      return parseStringLike(
        rawValue,
        context: path,
        allowEmpty: allowEmpty,
        throwOnInvalid: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Gets an optional string list from config.
  ///
  /// Returns null if the key doesn't exist or can't be converted to a string list.
  List<String>? getStringListOrNull(String path) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return null;

      return parseStringList(rawValue, context: path, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a Duration value from config, with automatic type conversion.
  ///
  /// Supports duration strings like '30s', '5m', '1h', etc.
  /// Numeric values are treated as seconds.
  /// Returns [defaultValue] if the key doesn't exist or can't be converted.
  Duration getDuration(String path, {Duration defaultValue = Duration.zero}) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return defaultValue;

      final parsed = parseDurationLike(
        rawValue,
        context: path,
        throwOnInvalid: false,
      );
      return parsed ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets an optional Duration value from config.
  ///
  /// Returns null if the key doesn't exist or can't be converted.
  Duration? getDurationOrNull(String path) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return null;

      return parseDurationLike(rawValue, context: path, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a string map from the config.
  Map<String, String> getStringMap(
    String path, {
    Map<String, String> defaultValue = const {},
  }) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return defaultValue;

      return parseStringMap(rawValue, context: path);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets a map of string lists from the config.
  Map<String, List<String>> getStringListMap(String path) {
    try {
      final rawValue = get<Object?>(path);
      if (rawValue == null) return {};
      return parseStringListMap(rawValue, context: path, throwOnInvalid: false);
    } catch (_) {
      return {};
    }
  }

  /// Gets a boolean value from config, throwing if not found or invalid.
  bool getBoolOrThrow(String path, {Map<String, bool>? stringMappings}) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseBoolLike(
      rawValue,
      context: path,
      stringMappings: stringMappings ?? const {'true': true, 'false': false},
      throwOnInvalid: true,
    )!;
  }

  /// Gets an integer value from config, throwing if not found or invalid.
  int getIntOrThrow(String path) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseIntLike(rawValue, context: path, throwOnInvalid: true)!;
  }

  /// Gets a string value from config, throwing if not found or invalid.
  String getStringOrThrow(String path, {bool allowEmpty = true}) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseStringLike(
      rawValue,
      context: path,
      allowEmpty: allowEmpty,
      throwOnInvalid: true,
    )!;
  }

  /// Gets a string list from config, throwing if not found or invalid.
  List<String> getStringListOrThrow(String path) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseStringList(
      rawValue,
      context: path,
      throwOnInvalid: true,
      allowEmptyResult: true,
    )!;
  }

  /// Gets a Duration value from config, throwing if not found or invalid.
  Duration getDurationOrThrow(String path) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseDurationLike(rawValue, context: path, throwOnInvalid: true)!;
  }

  /// Gets a string map from config, throwing if not found or invalid.
  Map<String, String> getStringMapOrThrow(String path) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseStringMap(rawValue, context: path);
  }

  /// Gets a map of string lists from config, throwing if not found or invalid.
  Map<String, List<String>> getStringListMapOrThrow(String path) {
    final rawValue = get<Object?>(path);
    if (rawValue == null) {
      throw ProviderConfigException('$path is required');
    }
    return parseStringListMap(rawValue, context: path, throwOnInvalid: true);
  }
}

/// Extension methods for parsing merged config maps (like those from ConfigMapCandidate).
extension MergedConfigUtils on Map<String, dynamic> {
  /// Gets a boolean value from a merged config map.
  ///
  /// Returns [defaultValue] if the key doesn't exist or can't be converted.
  bool getBool(
    String key, {
    bool defaultValue = false,
    Map<String, bool>? stringMappings,
  }) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return defaultValue;

      final parsed = parseBoolLike(
        rawValue,
        context: key,
        stringMappings: stringMappings ?? const {'true': true, 'false': false},
        throwOnInvalid: false,
      );
      return parsed ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Gets an optional boolean value from a merged config map.
  bool? getBoolOrNull(String key, {Map<String, bool>? stringMappings}) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseBoolLike(
        rawValue,
        context: key,
        stringMappings: stringMappings ?? const {'true': true, 'false': false},
        throwOnInvalid: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Gets a string list from a merged config map.
  List<String>? getStringList(String key) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseStringList(rawValue, context: key, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a string from a merged config map.
  String? getString(String key, {bool allowEmpty = true}) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseStringLike(
        rawValue,
        context: key,
        allowEmpty: allowEmpty,
        throwOnInvalid: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Gets an integer from a merged config map.
  int? getInt(String key) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseIntLike(rawValue, context: key, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a duration from a merged config map.
  Duration? getDuration(String key) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseDurationLike(rawValue, context: key, throwOnInvalid: false);
    } catch (_) {
      return null;
    }
  }

  /// Gets a string map from a merged config map.
  Map<String, String>? getStringMap(String key) {
    try {
      final rawValue = this[key];
      if (rawValue == null) return null;

      return parseStringMap(rawValue as Object, context: key);
    } catch (_) {
      return null;
    }
  }

  /// Gets a boolean value from a merged config map, throwing if not found or invalid.
  ///
  /// Supports string values like 'true', 'false', '1', '0', 'yes', 'no', 'on', 'off'.
  bool getBoolOrThrow(String key, {Map<String, bool>? stringMappings}) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseBoolLike(
      rawValue,
      context: key,
      stringMappings: stringMappings ?? const {'true': true, 'false': false},
      throwOnInvalid: true,
    )!;
  }

  /// Gets an integer value from a merged config map, throwing if not found or invalid.
  int getIntOrThrow(String key) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseIntLike(rawValue, context: key, throwOnInvalid: true)!;
  }

  /// Gets a string value from a merged config map, throwing if not found or invalid.
  String getStringOrThrow(String key, {bool allowEmpty = true}) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseStringLike(
      rawValue,
      context: key,
      allowEmpty: allowEmpty,
      throwOnInvalid: true,
    )!;
  }

  /// Gets a string list from a merged config map, throwing if not found or invalid.
  List<String> getStringListOrThrow(String key) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseStringList(
      rawValue,
      context: key,
      throwOnInvalid: true,
      allowEmptyResult: true,
    )!;
  }

  /// Gets a Duration value from a merged config map, throwing if not found or invalid.
  Duration getDurationOrThrow(String key) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseDurationLike(rawValue, context: key, throwOnInvalid: true)!;
  }

  /// Gets a string map from a merged config map, throwing if not found or invalid.
  Map<String, String> getStringMapOrThrow(String key) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseStringMap(rawValue as Object, context: key);
  }

  /// Gets a map of string lists from a merged config map, throwing if not found or invalid.
  Map<String, List<String>> getStringListMapOrThrow(String key) {
    final rawValue = this[key];
    if (rawValue == null) {
      throw ProviderConfigException('$key is required');
    }
    return parseStringListMap(rawValue, context: key, throwOnInvalid: true);
  }
}
