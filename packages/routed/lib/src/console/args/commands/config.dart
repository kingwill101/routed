import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/config/doc_printer.dart';
import 'package:routed/src/console/config/generator.dart';
import 'package:routed/src/console/util/dart_exec.dart';
import 'package:routed/src/console/util/pubspec.dart';

class ConfigInitCommand extends BaseCommand {
  ConfigInitCommand({super.logger, super.fileSystem}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing files.',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  String get name => 'config:init';

  @override
  String get description =>
      'Scaffold config/ and .env files for a new Routed project.';

  @override
  String get category => 'Configuration';

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        logger.error(
          'Could not locate a pubspec.yaml in the current directory.',
        );
        throw UsageException('Not a Routed project.', usage);
      }

      final force = results?['force'] as bool? ?? false;
      Map<String, List<ConfigDocEntry>> docsByRoot;
      try {
        docsByRoot = collectConfigDocs();
      } catch (_) {
        docsByRoot = const <String, List<ConfigDocEntry>>{};
      }

      final defaultsByRoot = buildConfigDefaults();
      final outputs = generateConfigFiles(defaultsByRoot, docsByRoot);
      final configRoot = fileSystem.directory(
        joinPath([projectRoot.path, 'config']),
      );
      await ensureDir(configRoot);

      final created = <String>[];
      for (final entry
          in outputs.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
        final target = fileSystem.file(joinPath([projectRoot.path, entry.key]));
        if (!force && await target.exists()) {
          logger.info(
            'Skipped existing ${_relative(projectRoot, target)} (use --force to overwrite)',
          );
          continue;
        }
        await writeTextFile(target, entry.value);
        created.add(entry.key);
        logger.info('Created ${_relative(projectRoot, target)}');
      }

      final envConfig = deriveEnvConfig(
        defaultsByRoot,
        docsByRoot,
        overrides: {
          'APP_NAME': 'Routed App',
          'APP_ENV': 'development',
          'APP_DEBUG': true,
          'APP_KEY': 'change-me',
          'SESSION_COOKIE': 'routed-session',
          'STORAGE_ROOT': 'storage/app',
          'OBSERVABILITY_TRACING_SERVICE_NAME': 'routed-service',
        },
      );
      final envContents = renderEnvFile(
        envConfig.values,
        extras: envConfig.commented,
      );

      final envPath = fileSystem.file(joinPath([projectRoot.path, '.env']));
      if (force || !await envPath.exists()) {
        await writeTextFile(envPath, envContents);
        logger.info('Created ${_relative(projectRoot, envPath)}');
      }

      final envExamplePath = fileSystem.file(
        joinPath([projectRoot.path, '.env.example']),
      );
      if (force || !await envExamplePath.exists()) {
        await writeTextFile(envExamplePath, envContents);
        logger.info('Created ${_relative(projectRoot, envExamplePath)}');
      }
    });
  }
}

class ConfigSchemaCommand extends BaseCommand {
  ConfigSchemaCommand({super.logger, super.fileSystem}) {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Path to the generated JSON Schema file.',
      defaultsTo: 'schemas/config.schema.json',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'config:schema';

  @override
  String get description =>
      'Generate a master JSON Schema for configuration validation.';

  @override
  String get category => 'Configuration';

  static const String _schemaTitle = 'Routed Configuration';
  static const String _schemaId =
      'https://raw.githubusercontent.com/kingwill101/routed/master/packages/routed/schemas/config.schema.json';

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      final output = results?['output'] as String;
      final target = fileSystem.file(
        projectRoot != null ? p.join(projectRoot.path, output) : output,
      );

      logger.debug('Inspecting providers...');
      final providers = projectRoot == null
          ? inspectProviders()
          : await _inspectProjectProviders(projectRoot) ?? inspectProviders();
      final registry = ConfigRegistry();

      for (final provider in providers) {
        if (provider.schemas.isNotEmpty) {
          registry.register(
            provider.defaults,
            source: provider.id,
            schemas: provider.schemas,
          );
        }
      }

      logger.debug('Generating schema...');
      final schema = registry.generateJsonSchema(
        title: _schemaTitle,
        id: _schemaId,
      );

      final json = const JsonEncoder.withIndent('  ').convert(schema);
      await target.parent.create(recursive: true);
      await target.writeAsString(json);

      if (projectRoot != null) {
        logger.info('Created ${_relative(projectRoot, target)}');
      } else {
        logger.info('Created ${target.path}');
      }
    });
  }

  Future<List<ProviderMetadata>?> _inspectProjectProviders(
    fs.Directory projectRoot,
  ) async {
    final appFile = fileSystem.file(
      joinPath([projectRoot.path, 'lib', 'app.dart']),
    );
    if (!await appFile.exists()) {
      return null;
    }

    final packageName = await readPackageName(projectRoot);
    if (packageName == null || packageName.isEmpty) {
      return null;
    }

    final scriptRelativePath = p.join(
      '.dart_tool',
      'routed',
      'inspect_providers.dart',
    );
    final scriptFile = fileSystem.file(
      joinPath([projectRoot.path, scriptRelativePath]),
    );
    await scriptFile.parent.create(recursive: true);

    final rootLiteral = jsonEncode(projectRoot.path);
    final scriptContents =
        '''
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  Directory.current = Directory($rootLiteral);
  final engine = await app.createEngine();
  final providers = inspectProviders();
  await engine.close();
  stdout.write(jsonEncode({
    'providers': providers.map((provider) => provider.toJson()).toList(),
  }));
}
''';
    await scriptFile.writeAsString(scriptContents);

    final result = await _runInspector(projectRoot, scriptRelativePath);
    if (result.exitCode != 0) {
      final message = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : 'Provider inspection failed with exit code ${result.exitCode}.';
      throw UsageException(message, usage);
    }

    final output = result.stdout.trim();
    if (output.isEmpty) {
      throw UsageException('Provider inspector produced no output.', usage);
    }

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Inspector output must be a JSON object.');
      }
      final providersRaw = decoded['providers'] as List<dynamic>? ?? const [];
      return providersRaw
          .whereType<Map<String, dynamic>>()
          .map(
            (entry) => ProviderMetadata.fromJson(
              entry.map((key, value) => MapEntry(key, value)),
            ),
          )
          .toList();
    } on FormatException catch (error) {
      throw UsageException(
        'Failed to parse provider inspector JSON: ${error.message}',
        usage,
      );
    }
  }
}

class _ProcessResult {
  _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<_ProcessResult> _runInspector(
  fs.Directory projectRoot,
  String entry,
) async {
  final process = await startDartProcess([
    'run',
    entry,
  ], workingDirectory: projectRoot.path);

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  await Future.wait([
    process.stdout
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write)
        .asFuture<void>(),
    process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>(),
  ]);

  final exitCode = await process.exitCode;
  return _ProcessResult(
    exitCode: exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: stderrBuffer.toString(),
  );
}

typedef PackageResolver =
    Future<fs.Directory?> Function(
      fs.Directory projectRoot,
      String packageName,
    );

class ConfigPublishCommand extends BaseCommand {
  ConfigPublishCommand({
    super.logger,
    super.fileSystem,
    PackageResolver? packageResolver,
  }) : _packageResolver = packageResolver ?? _resolvePackageRoot {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite existing files in config/ if they already exist.',
        negatable: false,
        defaultsTo: false,
      )
      ..addOption(
        'tag',
        help: 'Copy templates from config/stubs/<tag> when available.',
        valueHelp: 'tag',
      );
  }

  final PackageResolver _packageResolver;

  @override
  String get name => 'config:publish';

  @override
  String get description =>
      'Copy configuration stubs from a dependency into config/.';

  @override
  String get category => 'Configuration';

  @override
  Future<void> run() async {
    return guarded(() async {
      final packageName = results?.rest.isNotEmpty == true
          ? results!.rest.first
          : null;
      if (packageName == null) {
        throw UsageException('Specify a package name.', usage);
      }

      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        logger.error(
          'Could not locate a pubspec.yaml in the current directory.',
        );
        throw UsageException('Not a Routed project.', usage);
      }

      final packageRoot = await _packageResolver(projectRoot, packageName);
      if (packageRoot == null || !await packageRoot.exists()) {
        logger.error(
          'Package "$packageName" not found. Run `dart pub get` first.',
        );
        io.exitCode = 66;
        return;
      }

      final tag = results?['tag'] as String?;
      final stubsDir = await _resolveStubsDirectory(packageRoot, tag);
      Map<String, List<ConfigDocEntry>> docsByRoot;
      try {
        docsByRoot = collectConfigDocs();
      } catch (_) {
        docsByRoot = const <String, List<ConfigDocEntry>>{};
      }

      if (stubsDir == null) {
        final force = results?['force'] as bool? ?? false;
        if (packageName == 'routed') {
          logger.info(
            'No stubs found for routed; generating default templates.',
          );
          final defaultsByRoot = buildConfigDefaults();
          final outputs = generateConfigFiles(defaultsByRoot, docsByRoot);
          final configRoot = fileSystem.directory(
            joinPath([projectRoot.path, 'config']),
          );
          await ensureDir(configRoot);

          for (final entry
              in outputs.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))) {
            final target = fileSystem.file(
              joinPath([projectRoot.path, entry.key]),
            );
            if (!force && await target.exists()) {
              continue;
            }
            await writeTextFile(target, entry.value);
            logger.info('Created ${_relative(projectRoot, target)}');
          }

          final envConfig = deriveEnvConfig(
            defaultsByRoot,
            docsByRoot,
            overrides: {
              'APP_NAME': 'Routed App',
              'APP_ENV': 'development',
              'APP_DEBUG': true,
              'APP_KEY': 'change-me',
              'SESSION_COOKIE': 'routed-session',
              'STORAGE_ROOT': 'storage/app',
              'OBSERVABILITY_TRACING_SERVICE_NAME': 'routed-service',
            },
          );
          final envContents = renderEnvFile(
            envConfig.values,
            extras: envConfig.commented,
          );

          final envPath = fileSystem.file(joinPath([projectRoot.path, '.env']));
          if (force || !await envPath.exists()) {
            await writeTextFile(envPath, envContents);
            logger.info('Created ${_relative(projectRoot, envPath)}');
          }

          final envExamplePath = fileSystem.file(
            joinPath([projectRoot.path, '.env.example']),
          );
          if (force || !await envExamplePath.exists()) {
            await writeTextFile(envExamplePath, envContents);
            logger.info('Created ${_relative(projectRoot, envExamplePath)}');
          }
          return;
        }
        logger.error(
          'Package "$packageName" does not expose config stubs under config/stubs${tag != null ? '/$tag' : ''}.',
        );
        io.exitCode = 66;
        return;
      }

      final configRoot = fileSystem.directory(
        joinPath([projectRoot.path, 'config']),
      );
      await ensureDir(configRoot);
      final force = results?['force'] as bool? ?? false;

      final totalCopied = await _copyDirectory(
        source: stubsDir,
        destination: configRoot,
        projectRoot: projectRoot,
        force: force,
        fileSystem: fileSystem,
      );

      if (totalCopied == 0) {
        logger.info(
          'No files copied from ${_relative(projectRoot, stubsDir)}.',
        );
      } else {
        logger.info(
          'Copied $totalCopied file(s) from ${_relative(projectRoot, stubsDir)}.',
        );
      }
    });
  }
}

class ConfigCacheCommand extends BaseCommand {
  ConfigCacheCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to the generated Dart file containing the merged config.',
        defaultsTo: 'lib/generated/routed_config.dart',
        valueHelp: 'path',
      )
      ..addOption(
        'json-output',
        help: 'Optional JSON cache path for tooling.',
        defaultsTo: '.dart_tool/routed/config_cache.json',
        valueHelp: 'path',
      )
      ..addFlag(
        'pretty',
        help: 'Pretty-print the JSON cache.',
        negatable: true,
        defaultsTo: true,
      )
      ..addFlag(
        'docs',
        help: 'Emit configuration documentation metadata alongside caches.',
        defaultsTo: true,
      )
      ..addOption(
        'docs-output',
        help: 'Path to write configuration documentation metadata (JSON).',
        defaultsTo: '.dart_tool/routed/config_docs.json',
        valueHelp: 'path',
      );
  }

  @override
  String get name => 'config:cache';

  @override
  String get description =>
      'Merge configuration sources and write a generated cache file.';

  @override
  String get category => 'Configuration';

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        logger.error(
          'Could not locate a pubspec.yaml in the current directory.',
        );
        throw UsageException('Not a Routed project.', usage);
      }

      final configDir = fileSystem.directory(
        joinPath([projectRoot.path, 'config']),
      );
      if (!await configDir.exists()) {
        logger.error(
          'config/ directory not found. Run `routed config:init` first.',
        );
        io.exitCode = 66;
        return;
      }

      final envPath = joinPath([projectRoot.path, '.env']);
      final options = ConfigLoaderOptions(
        defaults: const {
          'app': {'name': 'Routed App', 'env': 'development', 'debug': true},
        },
        configDirectory: configDir.path,
        envFiles: [envPath],
        loadEnvFiles: true,
        includeEnvironmentSubdirectory: true,
        fileSystem: fileSystem,
      );

      final loader = ConfigLoader(fileSystem: fileSystem);
      final snapshot = loader.load(options);

      final outputPath = joinPath([
        projectRoot.path,
        results?['output'] as String,
      ]);
      final jsonOutputPath = joinPath([
        projectRoot.path,
        results?['json-output'] as String,
      ]);
      final pretty = results?['pretty'] as bool? ?? true;
      final writeDocs = results?['docs'] as bool? ?? true;
      final docsOutputPath = joinPath([
        projectRoot.path,
        results?['docs-output'] as String,
      ]);

      final dartOutput = fileSystem.file(outputPath);
      await _writeDartCache(dartOutput, snapshot);

      final jsonOutput = fileSystem.file(jsonOutputPath);
      await _writeJsonCache(jsonOutput, snapshot, pretty: pretty);

      logger.info('Wrote cache: ${_relative(projectRoot, dartOutput)}');
      logger.debug('JSON cache: ${_relative(projectRoot, jsonOutput)}');

      if (writeDocs && docsOutputPath.isNotEmpty) {
        final docsByRoot = collectConfigDocs();
        final docsFile = fileSystem.file(docsOutputPath);
        await docsFile.parent.create(recursive: true);
        await docsFile.writeAsString(renderConfigDocsJson(docsByRoot));
        logger.debug('Docs metadata: ${_relative(projectRoot, docsFile)}');
      }
    });
  }
}

class ConfigClearCommand extends BaseCommand {
  ConfigClearCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to the generated Dart cache to delete.',
        defaultsTo: 'lib/generated/routed_config.dart',
        valueHelp: 'path',
      )
      ..addOption(
        'json-output',
        help: 'Optional JSON cache path to delete.',
        defaultsTo: '.dart_tool/routed/config_cache.json',
        valueHelp: 'path',
      );
  }

  @override
  String get name => 'config:clear';

  @override
  String get description => 'Delete generated configuration cache artifacts.';

  @override
  String get category => 'Configuration';

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        logger.error(
          'Could not locate a pubspec.yaml in the current directory.',
        );
        throw UsageException('Not a Routed project.', usage);
      }

      final dartPath = joinPath([
        projectRoot.path,
        results?['output'] as String,
      ]);
      final jsonPath = joinPath([
        projectRoot.path,
        results?['json-output'] as String,
      ]);

      final removed = <String>[];

      for (final path in [dartPath, jsonPath]) {
        final file = fileSystem.file(path);
        if (await file.exists()) {
          await file.delete();
          removed.add(_relative(projectRoot, file));
        }
      }

      if (removed.isEmpty) {
        logger.info('No cache artifacts found.');
      } else {
        logger.info('Removed ${removed.join(', ')}');
      }
    });
  }
}

Future<fs.Directory?> _resolveStubsDirectory(
  fs.Directory packageRoot,
  String? tag,
) async {
  final fsInstance = packageRoot.fileSystem;
  final stubs = fsInstance.directory(
    p.join(packageRoot.path, 'config', 'stubs'),
  );
  if (!await stubs.exists()) {
    return null;
  }
  if (tag == null) {
    return stubs;
  }
  final tagDir = fsInstance.directory(p.join(stubs.path, tag));
  return await tagDir.exists() ? tagDir : stubs;
}

Future<fs.Directory?> _resolvePackageRoot(
  fs.Directory projectRoot,
  String packageName,
) async {
  final fsInstance = projectRoot.fileSystem;
  final packageConfig = fsInstance.file(
    p.join(projectRoot.path, '.dart_tool', 'package_config.json'),
  );
  if (!await packageConfig.exists()) {
    return null;
  }

  final decoded = jsonDecode(await packageConfig.readAsString());
  if (decoded is! Map) return null;
  final packages = decoded['packages'];
  if (packages is! List) return null;

  for (final entry in packages) {
    if (entry is! Map) continue;
    if (entry['name'] != packageName) continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) continue;
    final resolved = packageConfig.parent.uri.resolve(rootUri);
    final path = resolved.toFilePath();
    return fsInstance.directory(path);
  }
  return null;
}

Future<int> _copyDirectory({
  required fs.Directory source,
  required fs.Directory destination,
  required fs.Directory projectRoot,
  required bool force,
  required fs.FileSystem fileSystem,
}) async {
  var count = 0;

  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! fs.File) {
      continue;
    }
    final relative = p.relative(entity.path, from: source.path);
    final target = fileSystem.file(p.join(destination.path, relative));
    if (!force && await target.exists()) {
      continue;
    }
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
    count++;
  }
  return count;
}

Future<void> _writeJsonCache(
  fs.File file,
  ConfigSnapshot snapshot, {
  required bool pretty,
}) async {
  final encoder = pretty
      ? const JsonEncoder.withIndent('  ')
      : const JsonEncoder();
  final json = encoder.convert(snapshot.config.all());
  await file.parent.create(recursive: true);
  await file.writeAsString(json);
}

Future<void> _writeDartCache(fs.File file, ConfigSnapshot snapshot) async {
  await file.parent.create(recursive: true);
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Environment: ${snapshot.environment}')
    ..writeln()
    ..writeln(
      'const String routedConfigEnvironment = '
      "'${_escapeString(snapshot.environment)}';",
    )
    ..writeln('const Map<String, dynamic> routedConfig = <String, dynamic>{');
  _writeMapLiteral(buffer, snapshot.config.all(), 1);
  buffer.writeln('};');

  await file.writeAsString(buffer.toString());
}

void _writeMapLiteral(
  StringBuffer buffer,
  Map<String, dynamic> map,
  int indent,
) {
  final indentStr = _indent(indent);
  final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in entries) {
    buffer.write(indentStr);
    buffer.write("'");
    buffer.write(_escapeString(entry.key));
    buffer.write("': ");
    buffer.write(_toLiteral(entry.value, indent));
    buffer.writeln(',');
  }
}

String _toLiteral(dynamic value, int indent) {
  if (value is Map<String, dynamic>) {
    final buffer = StringBuffer()..writeln('<String, dynamic>{');
    _writeMapLiteral(buffer, value, indent + 1);
    buffer
      ..write(_indent(indent))
      ..write('}');
    return buffer.toString();
  }

  if (value is Map) {
    final converted = value.map(
      (key, dynamic v) => MapEntry(key.toString(), v),
    );
    return _toLiteral(converted, indent);
  }

  if (value is Iterable) {
    final buffer = StringBuffer()..writeln('<dynamic>[');
    for (final element in value) {
      buffer
        ..write(_indent(indent + 1))
        ..write(_toLiteral(element, indent + 1))
        ..writeln(',');
    }
    buffer
      ..write(_indent(indent))
      ..write(']');
    return buffer.toString();
  }

  if (value is String) {
    return "'${_escapeString(value)}'";
  }

  if (value is num || value is bool) {
    return value.toString();
  }

  if (value == null) {
    return 'null';
  }

  return "'${_escapeString(value.toString())}'";
}

String _indent(int level) => '  ' * level;

String _escapeString(String input) =>
    input.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

String _relative(fs.Directory root, fs.FileSystemEntity entity) =>
    p.relative(entity.path, from: root.path);
