import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' show ConfigDocEntry;
import 'package:routed_cli/src/args/base_command.dart';
import 'package:routed_cli/src/config/doc_printer.dart';
import 'package:routed_cli/src/config/generator.dart';
import 'package:routed_cli/src/util/dart_exec.dart';
import 'package:yaml/yaml.dart';

typedef PubGetInvoker = Future<int> Function(fs.Directory projectDir);

/// Creates a new Routed app with healthy defaults.
///
/// By default this command scaffolds a project using the "basic" template:
/// ```
/// routed create --name hello_world
/// ```
/// This produces:
/// - pubspec.yaml with routed dependency
/// - bin/server.dart with a starter route
/// - config/ files (same as `config:init`)
/// - analysis_options.yaml, README.md, .gitignore
///
/// Options:
/// - --name/-n: Project name (used for pubspec + folder when writing to current dir)
/// - --output/-o: Destination directory (defaults to current directory)
/// - --template/-t: Template to use (currently only "basic")
/// - --force/-f: Overwrite existing files when the target directory exists
class CreateCommand extends BaseCommand {
  CreateCommand({super.logger, super.fileSystem, PubGetInvoker? pubGet})
    : _pubGet = pubGet ?? _defaultPubGet {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'The project name (application + pubspec name).',
        valueHelp: 'my_app',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Directory where the project will be created.',
        valueHelp: 'path',
        defaultsTo: '.',
      )
      ..addOption(
        'template',
        abbr: 't',
        help: 'Application template to scaffold (currently only "basic").',
        valueHelp: 'basic',
        defaultsTo: 'basic',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite generated files when the target directory exists.',
        negatable: true,
        defaultsTo: false,
      );
  }

  final PubGetInvoker _pubGet;

  @override
  String get name => 'create';

  @override
  String get description => 'Scaffold a new Routed application.';

  @override
  String get category => 'Scaffolding';

  @override
  Future<void> run() async {
    return guarded(() async {
      final rawName = results?['name'] as String?;
      final outputArg = results?['output'] as String? ?? '.';
      final template = (results?['template'] as String? ?? 'basic').trim();
      final force = results?['force'] as bool? ?? false;

      if (template != 'basic') {
        throw UsageException(
          'Unsupported template "$template". Currently only "basic" is available.',
          usage,
        );
      }

      final outputDir = fileSystem.directory(outputArg).absolute;
      final hasExplicitName = rawName != null && rawName.trim().isNotEmpty;
      final resolvedName = _resolveProjectName(
        rawName,
        outputDir,
        hasExplicitName,
      );
      final packageName = _sanitizePackageName(resolvedName);
      final humanName = _humanizePackageName(packageName);

      final targetDir = hasExplicitName
          ? fileSystem.directory(joinPath([outputDir.path, packageName]))
          : outputDir;

      await _prepareTargetDirectory(targetDir, force: force);

      final routedVersion = await _resolvePackageVersion(
        'routed',
        'routed.dart',
      );
      final appKey = _generateAppKey();
      Map<String, List<ConfigDocEntry>> docsByRoot;
      try {
        docsByRoot = collectConfigDocs();
      } catch (_) {
        docsByRoot = const <String, List<ConfigDocEntry>>{};
      }

      final createdFiles = <String>[];
      Future<void> write(String relativePath, String contents) async {
        final file = fileSystem.file(joinPath([targetDir.path, relativePath]));
        await writeTextFile(file, contents);
        createdFiles.add(relativePath);
      }

      await write('pubspec.yaml', _renderPubspec(packageName, routedVersion));

      await write(
        'analysis_options.yaml',
        'include: package:lints/recommended.yaml\n',
      );

      await write('.gitignore', _gitignoreTemplate);

      await write('README.md', _renderReadme(humanName));

      await write('lib/app.dart', _renderAppDart(humanName));
      await write('bin/server.dart', _renderServerDart(packageName));
      await write(
        'tool/spec_manifest.dart',
        _renderSpecManifestScript(packageName),
      );

      final defaultsByRoot = buildConfigDefaults();
      final configOutputs = generateConfigFiles(
        defaultsByRoot,
        docsByRoot,
      ).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in configOutputs) {
        final content = entry.value;
        await write(entry.key, content);
      }

      await ensureDir(
        fileSystem.directory(joinPath([targetDir.path, 'storage', 'app'])),
      );
      await ensureDir(
        fileSystem.directory(
          joinPath([targetDir.path, 'storage', 'framework', 'sessions']),
        ),
      );
      await ensureDir(
        fileSystem.directory(
          joinPath([targetDir.path, 'storage', 'framework', 'cache']),
        ),
      );

      final envConfig = deriveEnvConfig(
        defaultsByRoot,
        docsByRoot,
        overrides: {
          'APP_NAME': humanName,
          'APP_ENV': 'development',
          'APP_DEBUG': true,
          'APP_KEY': appKey,
          'SESSION_COOKIE': '${packageName}_session',
          'OBSERVABILITY_TRACING_SERVICE_NAME': packageName,
        },
      );
      final envContent = renderEnvFile(
        envConfig.values,
        extras: envConfig.commented,
      );
      await write('.env', envContent);
      await write('.env.example', envContent);

      logger.info('✔ Created project "$packageName" in ${targetDir.path}');

      logger.info('');
      logger.info('Running dart pub get...');
      final pubExitCode = await _pubGet(targetDir);
      final pubGetSucceeded = pubExitCode == 0;
      if (pubGetSucceeded) {
        logger.info('Dependencies installed successfully.');
      } else {
        logger.warn(
          'dart pub get exited with code $pubExitCode. Run it manually if problems persist.',
        );
      }

      if (createdFiles.isNotEmpty) {
        logger.info('');
        logger.info('Scaffolded files:');
        for (final path in createdFiles) {
          logger.info('  • $path');
        }
      }

      final relativePath = p.relative(targetDir.path, from: cwd.path);

      logger.info('');
      logger.info('Next steps:');
      logger.info('  cd $relativePath');
      if (!pubGetSucceeded) {
        logger.info('  dart pub get');
      }
      logger.info('  dart run routed_cli dev');
    });
  }

  String _resolveProjectName(
    String? rawName,
    fs.Directory outputDir,
    bool hasExplicitName,
  ) {
    if (hasExplicitName) {
      return rawName!;
    }

    final base = p.basename(outputDir.path);
    if (outputDir.path == cwd.absolute.path || base == '.') {
      throw UsageException(
        'Provide --name when scaffolding inside the current directory, '
        'or specify --output to a new directory.',
        usage,
      );
    }
    return base;
  }

  Future<void> _prepareTargetDirectory(
    fs.Directory targetDir, {
    required bool force,
  }) async {
    if (await targetDir.exists()) {
      final isEmpty = await _directoryIsEmpty(targetDir);
      if (!isEmpty && !force) {
        throw UsageException(
          'Directory "${targetDir.path}" already exists. '
          'Use --force to overwrite generated files.',
          usage,
        );
      }
    } else {
      await ensureDir(targetDir);
    }
  }

  String _sanitizePackageName(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final isValid = RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized);
    if (!isValid) {
      throw UsageException(
        'Invalid package name "$name". '
        'Use lowercase letters, digits, and underscores (must start with a letter).',
        usage,
      );
    }
    return normalized;
  }

  String _humanizePackageName(String packageName) {
    return packageName
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  Future<bool> _directoryIsEmpty(fs.Directory dir) async {
    try {
      return await dir.list(followLinks: false).isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolvePackageVersion(
    String packageName,
    String libraryPath,
  ) async {
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:$packageName/$libraryPath'),
      );
      if (uri == null) return null;
      final libraryFile = io.File.fromUri(uri);
      final libDir = libraryFile.parent;
      final packageDir = libDir.parent;
      final pubspec = io.File(p.join(packageDir.path, 'pubspec.yaml'));
      if (!await pubspec.exists()) return null;
      final yaml = loadYaml(await pubspec.readAsString());
      if (yaml is YamlMap) {
        final version = yaml['version'];
        if (version != null) return version.toString();
      }
    } catch (_) {
      // Ignore and fall back to default.
    }
    return null;
  }

  String _renderPubspec(String packageName, String? routedVersion) {
    final versionConstraint = routedVersion != null ? '^$routedVersion' : 'any';

    return '''
name: $packageName
description: A new Routed application.
version: 0.1.0
publish_to: 'none'

environment:
  sdk: ">=3.9.2 <4.0.0"

dependencies:
  routed: $versionConstraint

dev_dependencies:
  lints: ^6.0.0
  test: ^1.26.3
''';
  }

  String _renderReadme(String humanName) {
    return '''
# $humanName

A new [Routed](https://routed.dev) application.

## Getting started

```bash
dart pub get
dart run routed_cli dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers.
''';
  }

  String _renderAppDart(String humanName) {
    final message = humanName.isEmpty ? 'Routed' : humanName;
    return '''
import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to $message!'});
  });

  return engine;
}
''';
  }

  String _renderServerDart(String packageName) {
    return '''
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  await engine.serve(host: '127.0.0.1', port: 8080);
}
''';
  }

  String _renderSpecManifestScript(String packageName) {
    return '''
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
''';
  }
}

const String _gitignoreTemplate = '''
.dart_tool/
.dart_tool/routed/
.packages

# Build and temporary outputs
build/

# Environment secrets
.env
.env.*

# Generated sources
lib/generated/
''';

String _generateAppKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64.encode(bytes);
}

Future<int> _defaultPubGet(fs.Directory projectDir) {
  return runDartProcess(
    ['pub', 'get'],
    workingDirectory: projectDir.path,
    mode: io.ProcessStartMode.inheritStdio,
  );
}
