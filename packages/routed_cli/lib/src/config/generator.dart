import 'dart:collection';
import 'dart:convert';

import 'package:json2yaml/json2yaml.dart';
import 'package:routed/routed.dart';
import 'package:yaml/yaml.dart' as yaml;

import 'doc_printer.dart';

/// Builds a map of configuration roots (e.g. "app", "http") to their default values
/// by merging the contributions from all registered service providers.
Map<String, Map<String, dynamic>> buildConfigDefaults() {
  final providers = inspectProviders();
  final merged = <String, Map<String, dynamic>>{};

  for (final provider in providers) {
    provider.defaults.forEach((root, value) {
      final existing = merged.putIfAbsent(root, () => <String, dynamic>{});
      if (value is Map<String, dynamic>) {
        _mergeMap(existing, value);
      } else if (value is Map) {
        _mergeMap(existing, _castToStringMap(value));
      } else {
        existing.clear();
        existing['value'] = _cloneValue(value);
      }
    });
  }

  _applyDerivedDefaults(merged);
  return merged;
}

/// Generates YAML content for each configuration root, keyed by the config path
/// (e.g. `config/app.yaml`).
void _applyDerivedDefaults(Map<String, Map<String, dynamic>> defaultsByRoot) {
  Map<String, dynamic> ensureMap(Map<String, dynamic> target, String key) {
    final current = target[key];
    if (current is Map<String, dynamic>) {
      return current;
    }
    if (current is Map) {
      final converted = _castToStringMap(current);
      target[key] = converted;
      return converted;
    }
    final created = <String, dynamic>{};
    target[key] = created;
    return created;
  }

  String? stringValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  final storage = defaultsByRoot.putIfAbsent(
    'storage',
    () => <String, dynamic>{},
  );
  final disks = ensureMap(storage, 'disks');
  final local = ensureMap(disks, 'local');
  final localRootValue = stringValue(local['root']) ?? 'storage/app';
  final storageDefaults = StorageDefaults.fromLocalRoot(localRootValue);
  local['root'] = storageDefaults.localDiskRoot;

  final session = defaultsByRoot.putIfAbsent(
    'session',
    () => <String, dynamic>{},
  );
  session.putIfAbsent('driver', () => 'file');
  session.putIfAbsent('files', () => storageDefaults.frameworkPath('sessions'));

  final cache = defaultsByRoot.putIfAbsent('cache', () => <String, dynamic>{});
  cache.putIfAbsent('default', () => 'file');
  final stores = ensureMap(cache, 'stores');
  final arrayStore = ensureMap(stores, 'array');
  arrayStore.putIfAbsent('driver', () => 'array');
  final fileStore = ensureMap(stores, 'file');
  fileStore.putIfAbsent('driver', () => 'file');
  final filePath = stringValue(fileStore['path']);
  fileStore['path'] = (filePath != null && filePath.trim().isNotEmpty)
      ? storageDefaults.resolve(filePath)
      : storageDefaults.frameworkPath('cache');
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
  final segments = path.split('.');
  if (segments.isEmpty) return null;
  final root = segments.first;
  dynamic current = defaultsByRoot[root];
  if (current == null) return null;
  for (var i = 1; i < segments.length; i++) {
    final segment = segments[i];
    if (current is Map<String, dynamic>) {
      if (!current.containsKey(segment)) return null;
      current = current[segment];
    } else if (current is Map) {
      if (!current.containsKey(segment)) return null;
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
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

Map<String, dynamic> _castToStringMap(Map<dynamic, dynamic> input) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    result[key.toString()] = value;
  });
  return result;
}

void _mergeMap(Map<String, dynamic> target, Map<String, dynamic> source) {
  for (final entry in source.entries) {
    final key = entry.key;
    final value = entry.value;
    if (!target.containsKey(key)) {
      target[key] = _cloneValue(value);
      continue;
    }

    final existing = target[key];
    if (existing is Map<String, dynamic> && value is Map<String, dynamic>) {
      _mergeMap(existing, value);
    } else if (existing is Map && value is Map) {
      final existingMap = _castToStringMap(existing);
      final valueMap = _castToStringMap(value);
      final typedExisting = <String, dynamic>{}..addAll(existingMap);
      target[key] = typedExisting;
      _mergeMap(typedExisting, valueMap);
    } else {
      target[key] = _cloneValue(value);
    }
  }
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> input) {
  final sorted = SplayTreeMap<String, dynamic>.of(input);
  final result = <String, dynamic>{};
  for (final entry in sorted.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      result[entry.key] = _sortedMap(value);
    } else if (value is Map) {
      result[entry.key] = _sortedMap(_castToStringMap(value));
    } else if (value is List) {
      result[entry.key] = value
          .map(
            (element) => element is Map<String, dynamic>
                ? _sortedMap(element)
                : element is Map
                ? _sortedMap(_castToStringMap(element))
                : element,
          )
          .toList();
    } else {
      result[entry.key] = value;
    }
  }
  return result;
}

Object? _cloneValue(Object? value) {
  if (value is Map<String, dynamic>) {
    final clone = <String, dynamic>{};
    value.forEach((key, element) {
      clone[key] = _cloneValue(element);
    });
    return clone;
  }
  if (value is Map) {
    final clone = <String, dynamic>{};
    value.forEach((key, element) {
      clone[key.toString()] = _cloneValue(element);
    });
    return clone;
  }
  if (value is List) {
    return value.map(_cloneValue).toList();
  }
  return value;
}

dynamic _prepareForYaml(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, element) => MapEntry(key, _prepareForYaml(element)));
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((key, dynamic element) {
      result[key.toString()] = _prepareForYaml(element);
    });
    return result;
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
