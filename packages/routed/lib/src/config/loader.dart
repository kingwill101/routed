import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:liquify/liquify.dart' as liquid;
import 'package:path/path.dart' as p;
import 'package:routed/src/config/config.dart';
import 'package:routed/src/utils/deep_copy.dart';
import 'package:yaml/yaml.dart';

class ConfigLoaderOptions {
  final Map<String, dynamic> defaults;
  final String configDirectory;
  final List<String> envFiles;
  final bool loadEnvFiles;
  final bool watch;
  final Duration watchDebounce;
  final String? environment;
  final bool includeEnvironmentSubdirectory;
  final FileSystem? fileSystem;

  const ConfigLoaderOptions({
    this.defaults = const <String, dynamic>{},
    this.configDirectory = 'config',
    this.envFiles = const ['.env'],
    this.loadEnvFiles = true,
    this.watch = false,
    this.watchDebounce = const Duration(milliseconds: 200),
    this.environment,
    this.includeEnvironmentSubdirectory = true,
    this.fileSystem,
  });

  ConfigLoaderOptions copyWith({
    Map<String, dynamic>? defaults,
    String? configDirectory,
    List<String>? envFiles,
    bool? loadEnvFiles,
    bool? watch,
    Duration? watchDebounce,
    String? environment,
    bool? includeEnvironmentSubdirectory,
    FileSystem? fileSystem,
  }) {
    return ConfigLoaderOptions(
      defaults: defaults ?? this.defaults,
      configDirectory: configDirectory ?? this.configDirectory,
      envFiles: envFiles ?? this.envFiles,
      loadEnvFiles: loadEnvFiles ?? this.loadEnvFiles,
      watch: watch ?? this.watch,
      watchDebounce: watchDebounce ?? this.watchDebounce,
      environment: environment ?? this.environment,
      includeEnvironmentSubdirectory:
          includeEnvironmentSubdirectory ?? this.includeEnvironmentSubdirectory,
      fileSystem: fileSystem ?? this.fileSystem,
    );
  }

  FileSystem get resolvedFileSystem =>
      fileSystem ?? const local.LocalFileSystem();
}

class ConfigSnapshot {
  final ConfigImpl config;
  final String environment;
  final Map<String, String> envVariables;
  final Map<String, dynamic> templateContext;

  ConfigSnapshot({
    required this.config,
    required this.environment,
    Map<String, String>? envVariables,
    Map<String, dynamic>? templateContext,
  }) : envVariables = envVariables ?? const <String, String>{},
       templateContext = templateContext ?? const <String, dynamic>{};
}

class ConfigLoader {
  ConfigLoader({FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem();

  final FileSystem _fileSystem;

  static const _supportedExtensions = <String>{
    '.yaml',
    '.yml',
    '.json',
    '.toml',
  };

  ConfigSnapshot load(
    ConfigLoaderOptions options, {
    Map<String, dynamic>? overrides,
  }) {
    final fs = options.fileSystem ?? _fileSystem;
    final pathContext = fs.path;
    final config = ConfigImpl();
    final envVariables = <String, String>{};

    var environment = _resolveInitialEnvironment(options, overrides);

    Map<String, dynamic>? envOverrides;
    if (options.loadEnvFiles) {
      final envResult = _loadEnvFiles(
        fs,
        options,
        seedEnvironment: environment,
      );
      envVariables.addAll(envResult.envVariables);
      envOverrides = envResult.configOverrides;
      if (envResult.environment != null && envResult.environment!.isNotEmpty) {
        environment = envResult.environment!;
      }
    }

    final templateContext = <String, dynamic>{};
    void addEnvEntry(String key, String value) {
      _addToTemplateContext(templateContext, key, value);
      _addToTemplateContext(templateContext, 'env.$key', value);
      if (key.contains('__')) {
        final normalized = _normalizeEnvKey(key);
        if (normalized != null && normalized != key) {
          _addToTemplateContext(templateContext, normalized, value);
          _addToTemplateContext(templateContext, 'env.$normalized', value);
        }
      }
    }

    Platform.environment.forEach(addEnvEntry);
    envVariables.forEach(addEnvEntry);
    if (overrides != null) {
      overrides.forEach((key, value) {
        _addToTemplateContext(templateContext, key, value);
        if (!key.contains('.')) {
          _addToTemplateContext(templateContext, 'env.$key', value);
          if (key.contains('__')) {
            final normalized = _normalizeEnvKey(key);
            if (normalized != null && normalized != key) {
              _addToTemplateContext(templateContext, 'env.$normalized', value);
            }
          }
        }
      });
    }

    final renderedDefaults = renderDefaults(options.defaults, templateContext);
    if (renderedDefaults.isNotEmpty) {
      config.mergeDefaults(renderedDefaults);
    }
    if (envOverrides != null && envOverrides.isNotEmpty) {
      config.merge(envOverrides);
    }

    _loadDirectoryConfigs(
      fs,
      options,
      config,
      environment: environment,
      templateContext: templateContext,
      pathContext: pathContext,
    );

    if (overrides != null && overrides.isNotEmpty) {
      config.merge(overrides);
    }

    if (!config.has('app.env') && environment.isNotEmpty) {
      config.set('app.env', environment);
    }

    return ConfigSnapshot(
      config: config,
      environment: environment,
      envVariables: envVariables,
      templateContext: deepCopyMap(templateContext),
    );
  }

  bool isWatchedFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _supportedExtensions.contains(ext) ||
        p.basename(path).startsWith('.env');
  }

  Map<String, dynamic> renderDefaults(
    Map<String, dynamic> defaults,
    Map<String, dynamic> templateContext,
  ) {
    if (defaults.isEmpty) {
      return const <String, dynamic>{};
    }
    return _renderDefaultsWithContext(defaults, templateContext);
  }

  Map<String, dynamic> _renderDefaultsWithContext(
    Map<String, dynamic> defaults,
    Map<String, dynamic> context,
  ) {
    if (defaults.isEmpty) {
      return const <String, dynamic>{};
    }
    final result = <String, dynamic>{};
    defaults.forEach((key, value) {
      final keyStr = key.toString();
      result[keyStr] = _renderTemplateNode(
        value,
        context,
        origin: 'defaults.$keyStr',
      );
    });
    return result;
  }

  dynamic _renderTemplateNode(
    Object? value,
    Map<String, dynamic> context, {
    required String origin,
  }) {
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, inner) {
        final keyStr = key?.toString() ?? '';
        if (keyStr.isEmpty) {
          return;
        }
        result[keyStr] = _renderTemplateNode(
          inner,
          context,
          origin: '$origin.$keyStr',
        );
      });
      return result;
    }
    if (value is Iterable) {
      final list = <dynamic>[];
      var index = 0;
      for (final entry in value) {
        list.add(
          _renderTemplateNode(entry, context, origin: '$origin[$index]'),
        );
        index++;
      }
      return list;
    }
    if (value is String && value.contains('{{')) {
      return _renderTemplate(value, context, origin);
    }
    return deepCopyValue(value);
  }

  _EnvLoadResult _loadEnvFiles(
    FileSystem fs,
    ConfigLoaderOptions options, {
    required String seedEnvironment,
  }) {
    final envVariables = <String, String>{};
    final configOverrides = <String, dynamic>{};

    final candidateFiles = <String>[...options.envFiles];

    if (seedEnvironment.isNotEmpty) {
      final envSpecific = options.envFiles
          .map(
            (file) => file.endsWith('.env')
                ? '$file.$seedEnvironment'
                : '$file.$seedEnvironment',
          )
          .toList();
      candidateFiles.addAll(envSpecific);
    }

    String? resolvedEnvironment = seedEnvironment;

    for (final candidate in candidateFiles) {
      final file = fs.file(candidate);
      if (!file.existsSync()) continue;
      final contents = file.readAsStringSync();
      final parsed = _parseEnvContents(contents);

      for (final entry in parsed.entries) {
        envVariables[entry.key] = entry.value;
        final normalized = _normalizeEnvKey(entry.key);
        if (normalized == null) continue;
        configOverrides[normalized] = entry.value;
        if (normalized == 'app.env') {
          resolvedEnvironment = entry.value;
        }
      }
    }

    return _EnvLoadResult(
      envVariables: envVariables,
      configOverrides: configOverrides,
      environment: resolvedEnvironment,
    );
  }

  void _loadDirectoryConfigs(
    FileSystem fs,
    ConfigLoaderOptions options,
    ConfigImpl config, {
    required String environment,
    required Map<String, dynamic> templateContext,
    required p.Context pathContext,
  }) {
    final baseDir = fs.directory(options.configDirectory);
    _mergeDirectory(config, baseDir, templateContext, pathContext);

    if (!options.includeEnvironmentSubdirectory || environment.isEmpty) {
      return;
    }

    final envDir = fs.directory(
      pathContext.join(options.configDirectory, environment),
    );
    _mergeDirectory(config, envDir, templateContext, pathContext);
  }

  void _mergeDirectory(
    ConfigImpl config,
    Directory directory,
    Map<String, dynamic> templateContext,
    p.Context pathContext,
  ) {
    if (!directory.existsSync()) {
      return;
    }

    final files =
        directory
            .listSync(recursive: false)
            .whereType<File>()
            .where(
              (file) => _supportedExtensions.contains(
                pathContext.extension(file.path).toLowerCase(),
              ),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final namespace = pathContext.basenameWithoutExtension(file.path);
      final content = _parseFile(file, templateContext, pathContext);
      if (content == null) continue;
      config.merge({namespace: content});
    }
  }

  Map<String, dynamic>? _parseFile(
    File file,
    Map<String, dynamic> templateContext,
    p.Context pathContext,
  ) {
    final ext = pathContext.extension(file.path).toLowerCase();
    try {
      final rawContents = file.readAsStringSync();
      final contents = _renderTemplate(rawContents, templateContext, file.path);
      switch (ext) {
        case '.json':
          final decoded = jsonDecode(contents);
          return _coerceToMap(decoded);
        case '.yaml':
        case '.yml':
          final yaml = loadYaml(contents);
          return _coerceToMap(yaml);
        case '.toml':
          return _parseToml(contents);
        default:
          return null;
      }
    } catch (error) {
      if (error is FormatException) {
        rethrow;
      }
      return null;
    }
  }

  Map<String, dynamic>? _coerceToMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return value.map(
        (key, dynamic v) =>
            MapEntry(key is String ? key : key.toString(), _coerceValue(v)),
      );
    }
    return null;
  }

  dynamic _coerceValue(dynamic value) {
    if (value is Map) {
      return _coerceToMap(value);
    }
    if (value is Iterable) {
      return value.map(_coerceValue).toList();
    }
    if (value is YamlScalar) {
      return value.value;
    }
    return value;
  }

  Map<String, dynamic>? _parseToml(String contents) {
    final result = <String, dynamic>{};
    final pathStack = <String>[];
    final lines = const LineSplitter().convert(contents);

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      if (line.startsWith('[[')) {
        // Arrays of tables are not currently supported; ignore.
        continue;
      }

      if (line.startsWith('[') && line.endsWith(']')) {
        final section = line.substring(1, line.length - 1).trim();
        if (section.isEmpty) {
          pathStack.clear();
          continue;
        }
        pathStack
          ..clear()
          ..addAll(section.split('.').map((segment) => segment.trim()));
        _ensureTomlPath(result, pathStack);
        continue;
      }

      final kvMatch = _tomlKeyValue.firstMatch(line);
      if (kvMatch == null) {
        continue;
      }

      final key = kvMatch.group(1)!.trim();
      final valueRaw = kvMatch.group(2)!.trim();
      final value = _parseTomlValue(valueRaw);
      final fullPath = <String>[...pathStack, key];
      _assignTomlValue(result, fullPath, value);
    }

    return result;
  }

  static final RegExp _tomlKeyValue = RegExp(r'^(.*?)\s*=\s*(.+)$');

  void _ensureTomlPath(Map<String, dynamic> root, List<String> path) {
    Map<String, dynamic> current = root;
    for (final segment in path) {
      current =
          current.putIfAbsent(segment, () => <String, dynamic>{})
              as Map<String, dynamic>;
    }
  }

  void _assignTomlValue(
    Map<String, dynamic> root,
    List<String> path,
    dynamic value,
  ) {
    if (path.isEmpty) return;
    Map<String, dynamic> current = root;
    for (var i = 0; i < path.length - 1; i++) {
      final segment = path[i];
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
      } else {
        final map = <String, dynamic>{};
        current[segment] = map;
        current = map;
      }
    }
    current[path.last] = value;
  }

  dynamic _parseTomlValue(String raw) {
    if (raw.isEmpty) return raw;

    if ((raw.startsWith('"') && raw.endsWith('"')) ||
        (raw.startsWith("'") && raw.endsWith("'"))) {
      return raw.substring(1, raw.length - 1);
    }

    if (raw.startsWith('{') && raw.endsWith('}')) {
      return _parseTomlInlineTable(raw);
    }

    if (raw.startsWith('[') && raw.endsWith(']')) {
      final items = _splitTomlList(raw.substring(1, raw.length - 1));
      return items.map((item) => _parseTomlValue(item.trim())).toList();
    }

    if (raw == 'true' || raw == 'false') {
      return raw == 'true';
    }

    final intValue = int.tryParse(raw);
    if (intValue != null) {
      return intValue;
    }

    final doubleValue = double.tryParse(raw);
    if (doubleValue != null) {
      return doubleValue;
    }

    return raw;
  }

  void _addToTemplateContext(
    Map<String, dynamic> context,
    String key,
    dynamic value,
  ) {
    if (!key.contains('.')) {
      context[key] = value;
      return;
    }

    final segments = key
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return;
    }

    dynamic current = context;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      final index = int.tryParse(segment);
      final nextIsIndex = !isLast && int.tryParse(segments[i + 1]) != null;

      if (index != null) {
        if (current is List<dynamic>) {
          while (current.length <= index) {
            current.add(null);
          }
          if (isLast) {
            current[index] = value;
          } else {
            var next = current[index];
            if (next == null ||
                (nextIsIndex && next is! List<dynamic>) ||
                (!nextIsIndex && next is! Map<String, dynamic>)) {
              next = nextIsIndex ? <dynamic>[] : <String, dynamic>{};
              current[index] = next;
            }
            current = current[index];
          }
          continue;
        }
        if (current is Map<String, dynamic>) {
          var list = current[segment];
          if (list is! List<dynamic>) {
            list = <dynamic>[];
            current[segment] = list;
          }
          current = list;
          i--; // Re-process this segment with the list as current.
          continue;
        }
        return;
      }

      if (current is! Map<String, dynamic>) {
        return;
      }

      if (isLast) {
        current[segment] = value;
      } else {
        var next = current[segment];
        if (next == null ||
            (nextIsIndex && next is! List<dynamic>) ||
            (!nextIsIndex && next is! Map<String, dynamic>)) {
          next = nextIsIndex ? <dynamic>[] : <String, dynamic>{};
          current[segment] = next;
        }
        current = next;
      }
    }
  }

  String _renderTemplate(
    String source,
    Map<String, dynamic> context,
    String origin,
  ) {
    if (context.isEmpty || !source.contains('{{')) {
      return source;
    }
    try {
      final template = liquid.Template.parse(source, data: context);
      final rendered = template.render();
      return rendered.toString();
    } catch (error) {
      throw FormatException(
        'Failed to render Liquid template in "$origin": $error',
      );
    }
  }

  Map<String, dynamic> _parseTomlInlineTable(String raw) {
    final result = <String, dynamic>{};
    final inner = raw.substring(1, raw.length - 1).trim();
    if (inner.isEmpty) return result;
    final pairs = _splitTomlList(inner);
    for (final pair in pairs) {
      final kvMatch = _tomlKeyValue.firstMatch(pair.trim());
      if (kvMatch == null) continue;
      final key = kvMatch.group(1)!.trim();
      final valueRaw = kvMatch.group(2)!.trim();
      result[key] = _parseTomlValue(valueRaw);
    }
    return result;
  }

  List<String> _splitTomlList(String raw) {
    final items = <String>[];
    final buffer = StringBuffer();
    var insideString = false;
    var stringDelimiter = '';
    var depth = 0;

    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (insideString) {
        buffer.write(char);
        if (char == stringDelimiter && raw[i - 1] != '\\') {
          insideString = false;
        }
        continue;
      }

      switch (char) {
        case '"':
        case "'":
          insideString = true;
          stringDelimiter = char;
          buffer.write(char);
          break;
        case '[':
        case '{':
          depth++;
          buffer.write(char);
          break;
        case ']':
        case '}':
          depth--;
          buffer.write(char);
          break;
        case ',':
          if (depth == 0) {
            items.add(buffer.toString());
            buffer.clear();
          } else {
            buffer.write(char);
          }
          break;
        default:
          buffer.write(char);
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      items.add(remaining);
    }
    return items;
  }

  String _resolveInitialEnvironment(
    ConfigLoaderOptions options,
    Map<String, dynamic>? overrides,
  ) {
    final potential =
        [
          options.environment,
          if (overrides != null) _extractEnv(overrides),
          _extractEnv(options.defaults),
          Platform.environment['APP_ENV'],
        ].firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => 'development',
        );
    return potential!;
  }

  String? _extractEnv(Map<String, dynamic> source) {
    final probe = ConfigImpl(source);
    final value = probe.get<String>('app.env');
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  String? _normalizeEnvKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase().replaceAll('__', '.');
  }

  Map<String, String> _parseEnvContents(String contents) {
    final result = <String, String>{};
    final lines = const LineSplitter().convert(contents);
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex == -1) {
        continue;
      }

      final key = line.substring(0, separatorIndex).trim();
      var value = line.substring(separatorIndex + 1).trim();

      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      result[key] = value;
    }
    return result;
  }
}

class _EnvLoadResult {
  final Map<String, String> envVariables;
  final Map<String, dynamic> configOverrides;
  final String? environment;

  _EnvLoadResult({
    required this.envVariables,
    required this.configOverrides,
    required this.environment,
  });
}
