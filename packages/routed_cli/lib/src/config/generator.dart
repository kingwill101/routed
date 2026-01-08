import 'dart:collection';
import 'dart:convert';

import 'package:json2yaml/json2yaml.dart';
import 'package:routed/routed.dart'
    show
        ConfigDocEntry,
        ConfigSchema,
        configDocMetaInheritFromEnv,
        deepCopyValue,
        deepMerge,
        dot,
        inspectProviders;
import 'package:yaml/yaml.dart' as yaml;

import 'doc_printer.dart';

/// Builds a map of configuration roots (e.g. "app", "http") to their default values
/// by merging the contributions from all registered service providers.
Map<String, Map<String, dynamic>> buildConfigDefaults() {
  final providers = inspectProviders();
  final merged = <String, Map<String, dynamic>>{};

  for (final provider in providers) {
    final Map<String, dynamic> defaults = Map.from(provider.defaults);

    // If schemas are available, use them to augment or provide defaults
    if (provider.schemas.isNotEmpty) {
      for (final entry in provider.schemas.entries) {
        final root = entry.key;
        final schema = entry.value;
        final schemaDefaults = ConfigSchema.extractDefaults(schema);
        if (schemaDefaults.isNotEmpty) {
          // Merge defaults into the specific root
          final rootDefaults = defaults.putIfAbsent(
              root, () => <String, dynamic>{});
          if (rootDefaults is Map<String, dynamic>) {
            deepMerge(rootDefaults, schemaDefaults, override: true);
          }
        }
      }
    }

    defaults.forEach((root, value) {
      final existing = merged.putIfAbsent(root, () => <String, dynamic>{});
      if (value is Map<String, dynamic>) {
        deepMerge(existing, value, override: true);
      } else if (value is Map) {
        deepMerge(existing, _stringKeyedClone(value), override: true);
      } else {
        existing
          ..clear()
          ..['value'] = deepCopyValue(value);
      }
    });
  }

  return merged;
}

Map<String, String> generateConfigFiles(
  Map<String, Map<String, dynamic>> defaultsByRoot,
  Map<String, List<ConfigDocEntry>> docsByRoot,
) {
  final outputs = <String, String>{};

  for (final entry in defaultsByRoot.entries) {
    final root = entry.key;
    final data = _sortedMap(entry.value);
    final prepared = _prepareForYaml(data);
    final yaml = _quoteTrailingColonValues(json2yaml(prepared));
    final path = 'config/$root.yaml';
    final withDocs = prependConfigDocComments(path, '$yaml\n', docsByRoot);
    outputs[path] = withDocs;
  }

  return outputs;
}

String renderEnvFile(
  Map<String, String> values, {
  Map<String, String?> extras = const {},
}) {
  final buffer = StringBuffer();
  final sortedKeys = values.keys.toList()..sort();
  for (final key in sortedKeys) {
    buffer.writeln('$key=${values[key]}');
  }
  if (extras.isNotEmpty) {
    buffer.writeln();
    final extraKeys = extras.keys.toList()..sort();
    for (final key in extraKeys) {
      final value = extras[key];
      buffer.writeln(value == null ? '# $key=' : '# $key=$value');
    }
  }
  return buffer.toString();
}

class EnvConfig {
  const EnvConfig({required this.values, required this.commented});

  final Map<String, String> values;
  final Map<String, String?> commented;
}

EnvConfig deriveEnvConfig(
  Map<String, Map<String, dynamic>> defaultsByRoot,
  Map<String, List<ConfigDocEntry>> docsByRoot, {
  Map<String, Object?> overrides = const {},
}) {
  final active = <String, String>{};
  final commented = <String, String?>{};
  final seen = <String>{};

  Iterable<ConfigDocEntry> allDocs() sync* {
    for (final entries in docsByRoot.values) {
      yield* entries;
    }
  }

  for (final entry in allDocs()) {
    final metadataValue = entry.metadata[configDocMetaInheritFromEnv];
    if (metadataValue == null) continue;
    final envKeys = _coerceEnvKeys(metadataValue);
    for (final envKey in envKeys) {
      if (envKey.isEmpty || seen.contains(envKey)) continue;

      Object? value;
      if (overrides.containsKey(envKey)) {
        value = overrides[envKey];
      } else {
        final configValue = _lookupConfigValue(defaultsByRoot, entry.path);
        value = configValue ?? entry.defaultValue;
      }
      final stringValue = _stringifyEnvValue(value);
      if (stringValue != null) {
        active[envKey] = stringValue;
      } else {
        commented[envKey] = null;
      }
      seen.add(envKey);
    }
  }

  for (final entry in overrides.entries) {
    final envKey = entry.key;
    if (seen.contains(envKey)) continue;
    final stringValue = _stringifyEnvValue(entry.value);
    if (stringValue != null) {
      active[envKey] = stringValue;
    } else {
      commented[envKey] = null;
    }
    seen.add(envKey);
  }

  return EnvConfig(values: active, commented: commented);
}

List<String> _coerceEnvKeys(Object metadataValue) {
  if (metadataValue is String) {
    return metadataValue.isEmpty ? const [] : <String>[metadataValue];
  }
  if (metadataValue is Iterable) {
    return metadataValue
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
  }
  return const [];
}

Object? _lookupConfigValue(
  Map<String, Map<String, dynamic>> defaultsByRoot,
  String path,
) {
  final flattened = <String, dynamic>{};
  defaultsByRoot.forEach((key, value) {
    flattened[key] = value;
  });
  return dot.get(flattened, path);
}

String? _stringifyEnvValue(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.toString();
  if (value is List || value is Map) {
    return jsonEncode(value);
  }
  return value.toString();
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> input) {
  final sorted = SplayTreeMap<String, dynamic>.of(input);
  final result = <String, dynamic>{};
  for (final entry in sorted.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      result[entry.key] = _sortedMap(value);
    } else if (value is Map) {
      result[entry.key] = _sortedMap(_stringKeyedClone(value));
    } else if (value is List) {
      result[entry.key] = value
          .map(
            (element) => element is Map<String, dynamic>
                ? _sortedMap(element)
                : element is Map
                ? _sortedMap(_stringKeyedClone(element))
                : element,
          )
          .toList();
    } else {
      result[entry.key] = value;
    }
  }
  return result;
}

dynamic _prepareForYaml(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, element) => MapEntry(key, _prepareForYaml(element)));
  }
  if (value is Map) {
    return _stringKeyedClone(
      value,
    ).map((key, element) => MapEntry(key, _prepareForYaml(element)));
  }
  if (value is List) {
    return value.map(_prepareForYaml).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.endsWith(':') && !trimmed.contains('{{')) {
      return yaml.YamlScalar.wrap(value, style: yaml.ScalarStyle.DOUBLE_QUOTED);
    }
  }
  return value;
}

String _quoteTrailingColonValues(String input) {
  final pattern = RegExp(
    r'^(\s*[^:\n]+:[ \t]*)([^"\n]*:)\s*$',
    multiLine: true,
  );
  return input.replaceAllMapped(pattern, (match) {
    final prefix = match.group(1)!;
    final value = match.group(2)!.trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      return match.group(0)!;
    }
    return '$prefix"$value"';
  });
}

Map<String, dynamic> _stringKeyedClone(Map<dynamic, dynamic> input) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    result[key.toString()] = _stringKeyedValue(value);
  });
  return result;
}

dynamic _stringKeyedValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return _stringKeyedClone(value);
  }
  if (value is Map) {
    return _stringKeyedClone(value);
  }
  if (value is List) {
    return value.map(_stringKeyedValue).toList();
  }
  return deepCopyValue(value);
}
