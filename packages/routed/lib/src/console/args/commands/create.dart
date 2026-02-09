import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' show ConfigDocEntry;
import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/config/doc_printer.dart';
import 'package:routed/src/console/config/generator.dart';
import 'package:routed/src/console/create/templates.dart';
import 'package:routed/src/console/util/dart_exec.dart';
import 'package:yaml/yaml.dart';

typedef PubGetInvoker = Future<int> Function(fs.Directory projectDir);
typedef InertiaCreateInvoker =
    Future<int> Function(
      fs.Directory projectDir,
      InertiaScaffoldOptions options,
    );
typedef InertiaPrompt = Future<bool> Function();

class InertiaScaffoldOptions {
  const InertiaScaffoldOptions({
    required this.framework,
    required this.packageManager,
    required this.output,
    required this.projectName,
    required this.force,
  });

  final String framework;
  final String packageManager;
  final String output;
  final String projectName;
  final bool force;
}

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
/// - --template/-t: Template to use (`basic`, `api`, `web`, `fullstack`)
/// - --force/-f: Overwrite existing files when the target directory exists
/// - --inertia/--no-inertia: Scaffold an Inertia client app
/// - --inertia-framework: Inertia framework adapter (`react`, `vue`, `svelte`)
/// - --inertia-package-manager: Package manager for the client (`npm`, `pnpm`, `yarn`, `bun`)
/// - --inertia-output: Output directory for the client app (default: `client`)
class CreateCommand extends BaseCommand {
  CreateCommand({
    super.logger,
    super.fileSystem,
    PubGetInvoker? pubGet,
    InertiaCreateInvoker? inertiaCreate,
    bool Function()? isInteractive,
    InertiaPrompt? inertiaPrompt,
  }) : _pubGet = pubGet ?? _defaultPubGet,
       _inertiaCreate = inertiaCreate ?? _defaultInertiaCreate,
       _isInteractive = isInteractive ?? _defaultIsInteractive,
       _inertiaPrompt = inertiaPrompt ?? _defaultInertiaPrompt {
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
        help: 'Application template to scaffold (basic, api, web, fullstack).',
        valueHelp: 'basic',
        defaultsTo: 'basic',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite generated files when the target directory exists.',
        negatable: true,
        defaultsTo: false,
      )
      ..addFlag(
        'inertia',
        help: 'Scaffold an Inertia client app (prompts when interactive).',
        negatable: true,
        defaultsTo: false,
      )
      ..addOption(
        'inertia-framework',
        help: 'Inertia framework adapter (react, vue, svelte).',
        allowed: const ['react', 'vue', 'svelte'],
        defaultsTo: 'react',
      )
      ..addOption(
        'inertia-package-manager',
        help: 'Package manager for the client (npm, pnpm, yarn, bun).',
        allowed: const ['npm', 'pnpm', 'yarn', 'bun'],
        defaultsTo: 'npm',
      )
      ..addOption(
        'inertia-output',
        help: 'Output directory for the client app (relative to project root).',
        valueHelp: 'client',
        defaultsTo: 'client',
      );
  }

  final PubGetInvoker _pubGet;
  final InertiaCreateInvoker _inertiaCreate;
  final bool Function() _isInteractive;
  final InertiaPrompt _inertiaPrompt;

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

      ScaffoldTemplate scaffoldTemplate;
      try {
        scaffoldTemplate = Templates.resolve(template);
      } on ArgumentError {
        throw UsageException(
          'Unsupported template "$template". Available templates: ${Templates.describe()}',
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
      logger.info(
        'Using template "${scaffoldTemplate.id}" (${scaffoldTemplate.description}).',
      );

      final workspaceRoot = await _findWorkspaceRoot(targetDir);
      final inWorkspace = workspaceRoot != null;

      final shouldScaffoldInertia = await _resolveInertiaChoice(results);
      final inertiaOptions = shouldScaffoldInertia
          ? _buildInertiaOptions(results)
          : null;

      final routedVersion = await _resolvePackageVersion(
        'routed',
        'routed.dart',
      );
      final routedInertiaVersion = shouldScaffoldInertia
          ? await _resolvePackageVersion(
              'routed_inertia',
              'routed_inertia.dart',
            )
          : null;
      final inertiaCliVersion = shouldScaffoldInertia
          ? await _resolvePackageVersion('inertia_dart', 'inertia_dart.dart')
          : null;
      final appKey = _generateAppKey();
      Map<String, List<ConfigDocEntry>> docsByRoot;
      try {
        docsByRoot = collectConfigDocs();
      } catch (_) {
        docsByRoot = const <String, List<ConfigDocEntry>>{};
      }

      final createdFiles = <String>[];
      final createdDirs = <String>[];
      Future<void> write(String relativePath, String contents) async {
        final file = fileSystem.file(joinPath([targetDir.path, relativePath]));
        await writeTextFile(file, contents);
        createdFiles.add(relativePath);
      }

      Future<void> scaffold(String relativePath) async {
        await ensureDir(
          fileSystem.directory(joinPath([targetDir.path, relativePath])),
        );
        createdDirs.add('$relativePath/');
      }

      final context = TemplateContext(
        packageName: packageName,
        humanName: humanName,
      );

      final extraDependencies = <String, String>{};
      final extraDevDependencies = <String, String>{};
      if (shouldScaffoldInertia) {
        extraDependencies['routed_inertia'] = _versionConstraint(
          routedInertiaVersion,
        );
        extraDevDependencies['inertia_dart'] = _versionConstraint(
          inertiaCliVersion,
        );
      }

      await write(
        'pubspec.yaml',
        _renderPubspec(
          packageName,
          routedVersion,
          scaffoldTemplate,
          extraDependencies: extraDependencies,
          extraDevDependencies: extraDevDependencies,
          inWorkspace: inWorkspace,
        ),
      );

      await write('README.md', scaffoldTemplate.renderReadme(context));

      for (final entry in scaffoldTemplate.fileBuilders.entries) {
        await write(entry.key, entry.value(context));
      }

      final defaultsByRoot = buildConfigDefaults();
      final configOutputs = generateConfigFiles(
        defaultsByRoot,
        docsByRoot,
      ).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in configOutputs) {
        final content = entry.value;
        await write(entry.key, content);
      }

      await scaffold('public');
      await scaffold('templates');
      await scaffold('storage/app');
      await scaffold('storage/framework/sessions');
      await scaffold('storage/framework/cache');

      final envConfig = deriveEnvConfig(
        defaultsByRoot,
        docsByRoot,
        overrides: {
          'APP_NAME': humanName,
          'APP_ENV': 'development',
          'APP_DEBUG': true,
          'APP_KEY': appKey,
          'SESSION_COOKIE': '${packageName}_session',
          'STORAGE_ROOT': 'storage/app',
          'OBSERVABILITY_TRACING_SERVICE_NAME': packageName,
        },
      );
      final envContent = renderEnvFile(
        envConfig.values,
        extras: envConfig.commented,
      );
      await write('.env', envContent);
      await write('.env.example', envContent);

      if (shouldScaffoldInertia) {
        await _applyInertiaBootstrap(targetDir, scaffoldTemplate.id, humanName);
      }

      if (inWorkspace) {
        await _addToWorkspace(workspaceRoot!, targetDir);
        logger.info('Added "$packageName" to workspace.');
      }

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

      if (shouldScaffoldInertia && inertiaOptions != null) {
        final inertiaExitCode = await _inertiaCreate(targetDir, inertiaOptions);
        if (inertiaExitCode != 0) {
          throw UsageException(
            'Inertia scaffolding failed (exit code $inertiaExitCode).',
            usage,
          );
        }
      }

      if (createdFiles.isNotEmpty || createdDirs.isNotEmpty) {
        logger.info('');
        logger.info('Scaffolded:');
        for (final dir in createdDirs) {
          logger.info('  📁 $dir');
        }
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
      logger.info('  dart run routed dev');
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

  String _renderPubspec(
    String packageName,
    String? routedVersion,
    ScaffoldTemplate template, {
    Map<String, String> extraDependencies = const {},
    Map<String, String> extraDevDependencies = const {},
    bool inWorkspace = false,
  }) {
    final versionConstraint = _versionConstraint(routedVersion);
    final dependencies = SplayTreeMap<String, String>.from({
      'args': '^2.5.0',
      'artisanal': '^0.1.2',
      'routed': versionConstraint,
      ...template.extraDependencies,
      ...extraDependencies,
    });
    final devDependencies = SplayTreeMap<String, String>.from({
      'lints': '^6.0.0',
      'test': '^1.26.3',
      ...template.extraDevDependencies,
      ...extraDevDependencies,
    });

    final buffer = StringBuffer()
      ..writeln('name: $packageName')
      ..writeln('description: A new Routed application.')
      ..writeln('version: 0.1.0')
      ..writeln("publish_to: 'none'");
    if (inWorkspace) {
      buffer.writeln('resolution: workspace');
    }
    buffer
      ..writeln()
      ..writeln('environment:')
      ..writeln('  sdk: ">=3.9.2 <4.0.0"')
      ..writeln()
      ..writeln('dependencies:');
    dependencies.forEach((name, constraint) {
      buffer.writeln('  $name: $constraint');
    });
    buffer.writeln();
    buffer.writeln('dev_dependencies:');
    devDependencies.forEach((name, constraint) {
      buffer.writeln('  $name: $constraint');
    });
    buffer.writeln();
    return buffer.toString();
  }

  Future<void> _applyInertiaBootstrap(
    fs.Directory targetDir,
    String templateId,
    String humanName,
  ) async {
    await _writeInertiaConfig(targetDir);
    await _writeInertiaView(targetDir);
    await _writeInertiaViewHelper(targetDir);
    await _patchHttpConfig(targetDir);
    await _patchStaticConfig(targetDir);
    await _patchAppFile(targetDir, templateId, humanName);
  }

  Future<void> _writeInertiaConfig(fs.Directory targetDir) async {
    final file = fileSystem.file(
      joinPath([targetDir.path, 'config/inertia.yaml']),
    );
    if (await file.exists()) return;
    final buffer = StringBuffer()
      ..writeln('version: "dev"')
      ..writeln('root_view: "inertia.liquid"')
      ..writeln('history:')
      ..writeln('  encrypt: false')
      ..writeln('ssr:')
      ..writeln('  enabled: false')
      ..writeln('  url: "http://127.0.0.1:13714"')
      ..writeln('  ensure_bundle_exists: true')
      ..writeln('  runtime: "node"')
      ..writeln('assets:')
      ..writeln('  manifest_path: "client/dist/.vite/manifest.json"')
      ..writeln('  entry: "index.html"')
      ..writeln('  base_url: "/"')
      ..writeln('  hot_file: "client/public/hot"');
    await writeTextFile(file, buffer.toString());
  }

  Future<void> _writeInertiaView(fs.Directory targetDir) async {
    final file = fileSystem.file(
      joinPath([targetDir.path, 'views/inertia.liquid']),
    );
    if (await file.exists()) return;
    const content = '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ props.title | default: "Routed App" }}</title>
    {{ ssrHead }}
    {{ inertia_styles }}
  </head>
  <body>
    {% if ssrBody != blank %}
      <div id="app" data-page="{{ pageJsonEscaped }}">{{ ssrBody }}</div>
    {% else %}
      <div id="app" data-page="{{ pageJsonEscaped }}"></div>
    {% endif %}
    {{ inertia_scripts }}
  </body>
</html>
''';
    await writeTextFile(file, content);
  }

  Future<void> _writeInertiaViewHelper(fs.Directory targetDir) async {
    final file = fileSystem.file(
      joinPath([targetDir.path, 'lib/inertia_views.dart']),
    );
    if (await file.exists()) return;
    const content = '''import 'package:routed/routed.dart';

void configureInertiaViews(Engine engine) {
  engine.useViewEngine(LiquidViewEngine(directory: 'views'));
}
''';
    await writeTextFile(file, content);
  }

  Future<void> _patchHttpConfig(fs.Directory targetDir) async {
    final file = fileSystem.file(
      joinPath([targetDir.path, 'config/http.yaml']),
    );
    if (!await file.exists()) return;
    var content = await file.readAsString();

    if (!content.contains('routed.inertia')) {
      content = _insertHttpProvider(content);
    }

    if (!content.contains('routed.inertia.middleware')) {
      content = _insertInertiaMiddlewareSource(content);
    }

    await file.writeAsString(content);
  }

  String _insertHttpProvider(String content) {
    const marker = '  - routed.views';
    const insertion = '  - routed.inertia';
    if (content.contains(insertion)) return content;
    if (content.contains(marker)) {
      return content.replaceFirst(marker, '$marker\n$insertion');
    }

    final providersIndex = content.indexOf('providers:');
    if (providersIndex == -1) return content;
    final insertAt = providersIndex + 'providers:'.length;
    return content.replaceRange(insertAt, insertAt, '\n$insertion');
  }

  String _insertInertiaMiddlewareSource(String content) {
    const block =
        '  routed.inertia:\n'
        '    global:\n'
        '      - routed.inertia.middleware\n';
    if (content.contains('routed.inertia:')) return content;

    final providersIndex = content.indexOf('\nproviders:');
    final middlewareIndex = content.indexOf('middleware_sources:');
    if (middlewareIndex == -1 || providersIndex == -1) {
      return content;
    }

    return content.replaceRange(
      providersIndex + 1,
      providersIndex + 1,
      '$block\n',
    );
  }

  Future<void> _patchStaticConfig(fs.Directory targetDir) async {
    final file = fileSystem.file(
      joinPath([targetDir.path, 'config/static.yaml']),
    );
    if (!await file.exists()) return;
    var content = await file.readAsString();
    content = content.replaceAll('enabled: false', 'enabled: true');
    if (!content.contains('route: /assets')) {
      final mountBlock =
          'mounts:\n'
          '  - route: /assets\n'
          '    path: client/dist/assets';
      content = content.replaceFirst(
        RegExp(r'^mounts:\s*$', multiLine: true),
        mountBlock,
      );
    }
    await file.writeAsString(content);
  }

  Future<void> _patchAppFile(
    fs.Directory targetDir,
    String templateId,
    String humanName,
  ) async {
    final file = fileSystem.file(joinPath([targetDir.path, 'lib/app.dart']));
    if (!await file.exists()) return;
    var content = await file.readAsString();

    content = _ensureImport(content, "import 'package:routed/providers.dart';");
    content = _ensureImport(content, "import 'inertia_views.dart';");
    content = _ensureImport(
      content,
      "import 'package:routed_inertia/routed_inertia.dart';",
    );

    if (!content.contains('registerRoutedInertiaProvider')) {
      const signature =
          'Future<Engine> createEngine({bool initialize = true}) async {';
      if (content.contains(signature)) {
        content = content.replaceFirst(
          signature,
          '$signature\n  registerRoutedInertiaProvider(ProviderRegistry.instance);\n',
        );
      }
    }

    if (!content.contains('ctx.inertia(')) {
      final route = templateId == 'basic' ? '/' : '/inertia';
      final inertiaBlock = _inertiaRouteBlock(route, humanName);
      content = _insertInertiaRoute(content, inertiaBlock);
    }

    if (templateId == 'basic') {
      content = _removeDefaultJsonRoute(content);
    }

    await file.writeAsString(content);
  }

  String _ensureImport(String content, String importLine) {
    if (content.contains(importLine)) return content;
    final matches = RegExp(
      r'^import\s+[^;]+;\s*$',
      multiLine: true,
    ).allMatches(content).toList();
    if (matches.isEmpty) {
      return '$importLine\n\n$content';
    }
    final last = matches.last;
    return content.replaceRange(last.end, last.end, '\n$importLine');
  }

  String _removeDefaultJsonRoute(String content) {
    final pattern = RegExp(
      r"engine\.get\('\/'\,\s*\(ctx\)\s*async\s*\{\s*return ctx\.json\(\{'message':\s*'Welcome to .*?'\}\);\s*\}\);",
    );
    return content.replaceFirst(pattern, '');
  }

  String _insertInertiaRoute(String content, String block) {
    const initBlock =
        '  if (initialize) {\n'
        '    await engine.initialize();\n'
        '  }\n';
    if (content.contains(initBlock)) {
      return content.replaceFirst(initBlock, '$initBlock\n$block');
    }

    const returnBlock = '  return engine;';
    if (content.contains(returnBlock)) {
      return content.replaceFirst(returnBlock, '$block\n  return engine;');
    }

    return content;
  }

  String _inertiaRouteBlock(String route, String humanName) {
    final title = humanName.replaceAll("'", "\\'");
    return '  configureInertiaViews(engine);\n\n'
        '  engine.get(\'$route\', (ctx) async {\n'
        '    return ctx.inertia(\n'
        '      \'Home\',\n'
        '      props: {\n'
        '        \'title\': \'$title\',\n'
        '        \'subtitle\': \'Routed + Inertia starter\',\n'
        '      },\n'
        '    );\n'
        '  });\n';
  }

  Future<bool> _resolveInertiaChoice(ArgResults? results) async {
    if (results == null) return false;
    final parsed = results.wasParsed('inertia');
    if (parsed) {
      return (results['inertia'] as bool?) ?? false;
    }
    if (!_isInteractive()) return false;
    return _inertiaPrompt();
  }

  InertiaScaffoldOptions _buildInertiaOptions(ArgResults? results) {
    final framework = (results?['inertia-framework'] as String? ?? 'react')
        .trim();
    final manager = (results?['inertia-package-manager'] as String? ?? 'npm')
        .trim();
    final rawOutput = results?['inertia-output'] as String?;
    final output = _normalizeInertiaOutput(rawOutput);
    final projectName = _deriveInertiaProjectName(output);
    final force = (results?['force'] as bool?) ?? false;
    return InertiaScaffoldOptions(
      framework: framework,
      packageManager: manager,
      output: output,
      projectName: projectName,
      force: force,
    );
  }

  String _normalizeInertiaOutput(String? rawOutput) {
    final trimmed = rawOutput?.trim() ?? '';
    if (trimmed.isEmpty) return 'client';
    final normalized = fileSystem.path.normalize(trimmed);
    if (normalized == '.' || normalized.isEmpty) return 'client';
    return normalized;
  }

  String _deriveInertiaProjectName(String output) {
    final base = fileSystem.path.basename(output);
    if (base.isEmpty || base == '.' || base == fileSystem.path.separator) {
      return 'client';
    }
    return base;
  }

  /// Walk up from [start] looking for a parent `pubspec.yaml` that contains
  /// a `workspace:` key (i.e. a Dart workspace root). Returns the directory
  /// containing that pubspec, or `null` if none is found.
  Future<fs.Directory?> _findWorkspaceRoot(fs.Directory start) async {
    var current = start.parent;
    for (var i = 0; i < 10; i++) {
      final pubspecFile = fileSystem.file(
        joinPath([current.path, 'pubspec.yaml']),
      );
      if (await pubspecFile.exists()) {
        try {
          final content = await pubspecFile.readAsString();
          final doc = loadYaml(content);
          if (doc is YamlMap && doc.containsKey('workspace')) {
            return current;
          }
        } catch (_) {
          // Malformed pubspec — skip.
        }
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }

  /// Add [targetDir] to the workspace member list in the workspace root
  /// pubspec.yaml. This is idempotent — if the member is already listed,
  /// no change is made.
  Future<void> _addToWorkspace(
    fs.Directory workspaceRoot,
    fs.Directory targetDir,
  ) async {
    final pubspecFile = fileSystem.file(
      joinPath([workspaceRoot.path, 'pubspec.yaml']),
    );
    if (!await pubspecFile.exists()) return;

    final relativePath = p.relative(targetDir.path, from: workspaceRoot.path);
    // Normalise to posix separators for YAML consistency.
    final posixPath = relativePath.replaceAll(r'\', '/');

    var content = await pubspecFile.readAsString();

    // Check if the member is already listed.
    final doc = loadYaml(content);
    if (doc is YamlMap && doc['workspace'] is YamlList) {
      final members = (doc['workspace'] as YamlList).toList();
      if (members.any((m) => m.toString() == posixPath)) {
        return; // Already a member.
      }
    }

    // Append the new member to the workspace list.
    final workspaceMatch = RegExp(
      r'^(workspace:\s*\n)((?:\s+-\s+.+\n)*)',
      multiLine: true,
    ).firstMatch(content);
    if (workspaceMatch != null) {
      final insertAt = workspaceMatch.end;
      content = content.replaceRange(insertAt, insertAt, '  - $posixPath\n');
    }

    await pubspecFile.writeAsString(content);
  }
}

String _generateAppKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64.encode(bytes);
}

String _versionConstraint(String? version) {
  return version != null ? '^$version' : 'any';
}

Future<int> _defaultPubGet(fs.Directory projectDir) {
  return runDartProcess(
    ['pub', 'get'],
    workingDirectory: projectDir.path,
    environment: io.Platform.environment,
    mode: io.ProcessStartMode.inheritStdio,
  );
}

Future<int> _defaultInertiaCreate(
  fs.Directory projectDir,
  InertiaScaffoldOptions options,
) {
  final workingDirectory = _resolveInertiaWorkingDirectory(projectDir);
  final output = _resolveInertiaOutput(
    workingDirectory: workingDirectory,
    projectDir: projectDir.path,
    output: options.output,
  );
  return runDartProcess(
    [
      'run',
      'inertia_dart:inertia',
      'create',
      options.projectName,
      if (options.force) '--force',
      '--output',
      output,
      '--framework',
      options.framework,
      '--package-manager',
      options.packageManager,
    ],
    workingDirectory: workingDirectory,
    environment: io.Platform.environment,
    mode: io.ProcessStartMode.inheritStdio,
  );
}

String _resolveInertiaWorkingDirectory(fs.Directory projectDir) {
  final cwd = io.Directory.current;
  final localInertiaPubspec = io.File(
    p.join(cwd.path, 'packages', 'inertia', 'pubspec.yaml'),
  );
  if (localInertiaPubspec.existsSync()) {
    return cwd.path;
  }
  return projectDir.path;
}

String _resolveInertiaOutput({
  required String workingDirectory,
  required String projectDir,
  required String output,
}) {
  if (workingDirectory == projectDir) {
    return output;
  }
  final desired = p.normalize(p.join(projectDir, output));
  final relative = p.relative(desired, from: workingDirectory);
  return relative.isEmpty || relative == '.' ? output : relative;
}

bool _defaultIsInteractive() {
  return io.stdin.hasTerminal && io.stdout.hasTerminal;
}

Future<bool> _defaultInertiaPrompt() async {
  while (true) {
    io.stdout.write('Add an Inertia client app? (y/N): ');
    final response = io.stdin.readLineSync();
    if (response == null) return false;
    final normalized = response.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'n' || normalized == 'no') {
      return false;
    }
    if (normalized == 'y' || normalized == 'yes') {
      return true;
    }
    io.stdout.writeln('Please enter y or n.');
  }
}
