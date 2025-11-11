import 'dart:convert';

import 'package:file/file.dart' as file;
import 'package:yaml/yaml.dart';

import 'package:routed/src/contracts/translation/loader.dart';
import 'package:routed/src/utils/deep_merge.dart';

class FileTranslationLoader implements TranslationLoader {
  FileTranslationLoader({
    required file.FileSystem fileSystem,
    Iterable<String>? paths,
    Iterable<String>? jsonPaths,
    Map<String, String>? namespaces,
  })  : _fileSystem = fileSystem,
        _paths = <String>[],
        _jsonPaths = <String>[],
        _namespaces = <String, String>{} {
    setPaths(paths ?? const ['resources/lang']);
    setJsonPaths(jsonPaths ?? const <String>[]);
    setNamespaces(namespaces ?? const <String, String>{});
  }

  final file.FileSystem _fileSystem;
  final List<String> _paths;
  final List<String> _jsonPaths;
  final Map<String, String> _namespaces;

  @override
  List<String> get paths => List.unmodifiable(_paths);

  @override
  List<String> get jsonPaths => List.unmodifiable(_jsonPaths);

  @override
  Map<String, String> get namespaces => Map.unmodifiable(_namespaces);

  @override
  Map<String, dynamic> load(
    String locale,
    String group, {
    String? namespace,
  }) {
    final normalizedGroup = group.isEmpty ? '*' : group;
    final normalizedNamespace = namespace?.isEmpty ?? true ? '*' : namespace!;
    if (normalizedGroup == '*' && normalizedNamespace == '*') {
      return _loadJsonPaths(locale);
    }
    if (normalizedNamespace == '*') {
      return _loadPaths(_paths, locale, normalizedGroup);
    }
    final hint = _namespaces[normalizedNamespace];
    if (hint == null) {
      return const {};
    }
    final base = _loadPaths([hint], locale, normalizedGroup);
    return _loadNamespaceOverrides(
        base, locale, normalizedGroup, normalizedNamespace);
  }

  @override
  void addNamespace(String namespace, String hint) {
    _namespaces[namespace] = _normalizePath(hint);
  }

  @override
  void setPaths(Iterable<String> paths) {
    _paths
      ..clear()
      ..addAll(paths.map(_normalizePath).where((path) => path.isNotEmpty));
  }

  @override
  void addPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return;
    }
    if (_paths.contains(normalized)) {
      return;
    }
    _paths.add(normalized);
  }

  @override
  void setJsonPaths(Iterable<String> paths) {
    _jsonPaths
      ..clear()
      ..addAll(paths.map(_normalizePath).where((path) => path.isNotEmpty));
  }

  @override
  void addJsonPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return;
    }
    if (_jsonPaths.contains(normalized)) {
      return;
    }
    _jsonPaths.add(normalized);
  }

  @override
  void setNamespaces(Map<String, String> namespaces) {
    _namespaces
      ..clear()
      ..addAll(namespaces.map(
        (key, value) => MapEntry(key, _normalizePath(value)),
      ));
  }

  Map<String, dynamic> _loadNamespaceOverrides(
    Map<String, dynamic> lines,
    String locale,
    String group,
    String namespace,
  ) {
    final merged = <String, dynamic>{};
    deepMerge(merged, lines, override: true);
    for (final path in _paths) {
      final vendorPath = _fileSystem.path.join(path, 'vendor', namespace);
      final overrides = _loadGroupFromDirectory(vendorPath, locale, group);
      if (overrides.isEmpty) {
        continue;
      }
      deepMerge(merged, overrides, override: true);
    }
    return merged;
  }

  Map<String, dynamic> _loadPaths(
    Iterable<String> paths,
    String locale,
    String group,
  ) {
    final merged = <String, dynamic>{};
    for (final base in paths) {
      final lines = _loadGroupFromDirectory(base, locale, group);
      if (lines.isEmpty) {
        continue;
      }
      deepMerge(merged, lines, override: true);
    }
    return merged;
  }

  Map<String, dynamic> _loadJsonPaths(String locale) {
    final merged = <String, dynamic>{};
    final combinedPaths = [..._jsonPaths, ..._paths];
    for (final base in combinedPaths) {
      final context = _fileSystem.path;
      final candidate = context.join(base, '$locale.json');
      final fileHandle = _fileSystem.file(candidate);
      if (!fileHandle.existsSync()) {
        continue;
      }
      final contents = fileHandle.readAsStringSync();
      final decoded = json.decode(contents);
      if (decoded is Map) {
        deepMerge(merged, _normalizeDynamicMap(decoded), override: true);
      } else {
        throw FormatException(
          'Translation file $candidate must decode to an object',
        );
      }
    }
    return merged;
  }

  Map<String, dynamic> _loadGroupFromDirectory(
    String basePath,
    String locale,
    String group,
  ) {
    final context = _fileSystem.path;
    final directory = context.join(basePath, locale);
    final candidates = <String>[
      context.join(directory, '$group.yaml'),
      context.join(directory, '$group.yml'),
      context.join(directory, '$group.json'),
    ];
    for (final candidate in candidates) {
      final fileHandle = _fileSystem.file(candidate);
      if (!fileHandle.existsSync()) {
        continue;
      }
      return _parseFile(fileHandle);
    }
    return const {};
  }

  Map<String, dynamic> _parseFile(file.File handle) {
    final extension = _fileSystem.path.extension(handle.path).toLowerCase();
    final contents = handle.readAsStringSync();
    if (extension == '.json') {
      final decoded = json.decode(contents);
      if (decoded is Map) {
        return _normalizeDynamicMap(decoded);
      }
      throw FormatException(
        'Translation file ${handle.path} must decode to an object',
      );
    }
    final parsed = loadYaml(contents);
    if (parsed == null) {
      return <String, dynamic>{};
    }
    if (parsed is YamlMap) {
      return _normalizeYamlMap(parsed);
    }
    if (parsed is Map) {
      return _normalizeDynamicMap(parsed);
    }
    throw FormatException(
      'Translation file ${handle.path} must contain a map of keys',
    );
  }

  Map<String, dynamic> _normalizeYamlMap(YamlMap map) {
    final result = <String, dynamic>{};
    map.nodes.forEach((keyNode, valueNode) {
      final key = keyNode.value?.toString();
      if (key == null) {
        return;
      }
      result[key] = _coerceValue(valueNode.value);
    });
    return result;
  }

  Map<String, dynamic> _normalizeDynamicMap(Map<dynamic, dynamic> input) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      if (key == null) {
        return;
      }
      result[key.toString()] = _coerceValue(value);
    });
    return result;
  }

  dynamic _coerceValue(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      return _normalizeDynamicMap(value);
    }
    if (value is YamlMap) {
      return _normalizeYamlMap(value);
    }
    if (value is Iterable) {
      return value.map(_coerceValue).toList();
    }
    return value;
  }

  String _normalizePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return _fileSystem.path.normalize(trimmed);
  }
}
