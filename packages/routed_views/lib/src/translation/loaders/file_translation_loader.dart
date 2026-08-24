import 'dart:convert';

import 'package:file/file.dart' as file;
import 'package:routed_core/routed_core.dart' show TranslationLoader, deepMerge;
import 'package:yaml/yaml.dart';

/// Loads grouped and flat JSON translations from a `file.FileSystem`.
///
/// Grouped files are searched beneath each configured path using the layout
/// `<path>/<locale>/<group>.<extension>`, where the supported extensions are
/// `.yaml`, `.yml`, and `.json`. Flat dictionaries use
/// `<path>/<locale>.json`. Matching maps are deep-merged in path order, so a
/// later path can override selected values without replacing the whole map.
///
/// For example, the default path supports files such as:
///
/// ```text
/// resources/lang/en/messages.yaml
/// resources/lang/en.json
/// ```
///
/// Namespace lookups use the configured source path and then apply optional
/// application overrides from `vendor/<namespace>` beneath the grouped search
/// paths.
class FileTranslationLoader implements TranslationLoader {
  /// Creates a loader with optional grouped, JSON, and namespace paths.
  ///
  /// [paths] defaults to `resources/lang`. [jsonPaths] defaults to an empty
  /// list, although flat JSON files in [paths] are also considered. Every path
  /// is trimmed and normalized; blank paths are ignored.
  FileTranslationLoader({
    required file.FileSystem fileSystem,
    Iterable<String>? paths,
    Iterable<String>? jsonPaths,
    Map<String, String>? namespaces,
  }) : _fileSystem = fileSystem,
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

  /// The ordered grouped-translation search paths.
  ///
  /// The returned list is an immutable snapshot. When several paths contain
  /// the requested file, later paths are merged over earlier paths.
  @override
  List<String> get paths => List.unmodifiable(_paths);

  /// The ordered flat-JSON translation search paths.
  ///
  /// The returned list is an immutable snapshot. These paths are searched
  /// before [paths] when loading a flat dictionary.
  @override
  List<String> get jsonPaths => List.unmodifiable(_jsonPaths);

  /// The configured namespace-to-source-path mappings.
  ///
  /// The returned map is immutable. A namespace source is used as the base
  /// for grouped files before application vendor overrides are merged.
  @override
  Map<String, String> get namespaces => Map.unmodifiable(_namespaces);

  /// Loads the map identified by [locale], [group], and optional [namespace].
  ///
  /// Use `group: '*'` and `namespace: '*'` to load a flat JSON dictionary. For
  /// grouped translations, an omitted or wildcard namespace searches [paths].
  /// A named namespace must have been registered with [addNamespace]; unknown
  /// namespaces return an empty map. Missing files also return an empty map.
  ///
  /// Malformed JSON or YAML, and translation files whose top-level value is
  /// not a map, throw [FormatException].
  @override
  Map<String, dynamic> load(String locale, String group, {String? namespace}) {
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
      base,
      locale,
      normalizedGroup,
      normalizedNamespace,
    );
  }

  /// Registers [namespace] with its source [hint], replacing an existing hint.
  ///
  /// For this file-backed implementation, [hint] is normalized as a path and
  /// used as the base directory for grouped files in that namespace.
  @override
  void addNamespace(String namespace, String hint) {
    _namespaces[namespace] = _normalizePath(hint);
  }

  /// Replaces the ordered grouped-translation search paths with [paths].
  ///
  /// Paths are normalized and blank entries are discarded.
  @override
  void setPaths(Iterable<String> paths) {
    _paths
      ..clear()
      ..addAll(paths.map(_normalizePath).where((path) => path.isNotEmpty));
  }

  /// Adds [path] to the grouped-translation search paths if it is new.
  ///
  /// Blank paths and normalized duplicates are ignored.
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

  /// Replaces the ordered flat-JSON search paths with [paths].
  ///
  /// Paths are normalized and blank entries are discarded.
  @override
  void setJsonPaths(Iterable<String> paths) {
    _jsonPaths
      ..clear()
      ..addAll(paths.map(_normalizePath).where((path) => path.isNotEmpty));
  }

  /// Adds [path] to the flat-JSON search paths if it is new.
  ///
  /// Blank paths and normalized duplicates are ignored.
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

  /// Replaces all namespace-to-source mappings with [namespaces].
  ///
  /// Namespace names are retained as supplied; source hints are normalized as
  /// paths. Namespaces omitted from the map are removed.
  @override
  void setNamespaces(Map<String, String> namespaces) {
    _namespaces
      ..clear()
      ..addAll(
        namespaces.map((key, value) => MapEntry(key, _normalizePath(value))),
      );
  }

  Map<String, dynamic> _loadNamespaceOverrides(
    Map<String, dynamic> lines,
    String locale,
    String group,
    String namespace,
  ) {
    final merged = <String, dynamic>{};
    deepMerge(merged, lines);
    for (final path in _paths) {
      final vendorPath = _fileSystem.path.join(path, 'vendor', namespace);
      final overrides = _loadGroupFromDirectory(vendorPath, locale, group);
      if (overrides.isEmpty) {
        continue;
      }
      deepMerge(merged, overrides);
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
      deepMerge(merged, lines);
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
        deepMerge(merged, _normalizeDynamicMap(decoded));
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
    for (final entry in map.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final valueNode = entry.value;
      final key = (keyNode.value as Object?)?.toString();
      if (key == null) {
        continue;
      }
      result[key] = _coerceValue(valueNode.value);
    }
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
