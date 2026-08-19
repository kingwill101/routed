import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/console/args/base_command.dart';
import 'package:routed_cli/src/console/create/templates.dart';
import 'package:routed_cli/src/console/util/dart_exec.dart';
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
/// - analysis_options.yaml, README.md, .gitignore
///
/// Options:
/// - --name/-n: Project name (used for pubspec + folder when writing to current dir)
/// - --output/-o: Destination directory (defaults to current directory)
/// - --template/-t: Template to use (`basic`, `api`, `web`, `fullstack`)
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

      final routedVersion = await _resolvePackageVersion(
        'routed',
        'routed.dart',
      );
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

      await write(
        'pubspec.yaml',
        _renderPubspec(
          packageName,
          routedVersion,
          scaffoldTemplate,
          inWorkspace: inWorkspace,
        ),
      );

      await write('README.md', scaffoldTemplate.renderReadme(context));

      for (final entry in scaffoldTemplate.fileBuilders.entries) {
        await write(entry.key, entry.value(context));
      }

      await scaffold('public');
      await scaffold('templates');
      await scaffold('storage/app');
      await scaffold('storage/framework/sessions');
      await scaffold('storage/framework/cache');

      if (inWorkspace) {
        await _addToWorkspace(workspaceRoot, targetDir);
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
      buffer.writeln('  $name: ${_formatDependencyConstraint(constraint)}');
    });
    buffer.writeln();
    buffer.writeln('dev_dependencies:');
    devDependencies.forEach((name, constraint) {
      buffer.writeln('  $name: ${_formatDependencyConstraint(constraint)}');
    });
    buffer.writeln();
    return buffer.toString();
  }

  String _formatDependencyConstraint(String constraint) {
    if (!constraint.contains(RegExp(r'\s'))) return constraint;
    final escaped = constraint.replaceAll('"', '\\"');
    return '"$escaped"';
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
