import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:routed_cli/routed_cli.dart' show CliLogger;
import 'package:routed_cli/src/console/args/commands/create.dart';
import 'package:routed_cli/src/console/args/runner.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('CreateCommand', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory workspace;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;
    late List<fs.Directory> pubGetInvocations;
    late int pubGetExitCode;

    setUp(() {
      memoryFs = MemoryFileSystem();
      workspace = memoryFs.directory('/workspace')..createSync(recursive: true);
      memoryFs.currentDirectory = workspace;

      logger = _RecordingLogger();
      pubGetInvocations = <fs.Directory>[];
      pubGetExitCode = 0;
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          CreateCommand(
            logger: logger,
            fileSystem: memoryFs,
            pubGet: (projectDir) async {
              pubGetInvocations.add(projectDir);
              return pubGetExitCode;
            },
          ),
        ]);
    });

    test('scaffolds a new project with defaults', () async {
      await _run(runner, ['create', '--name', 'demo_app']);

      final projectDir = memoryFs.directory(
        memoryFs.path.join(workspace.path, 'demo_app'),
      );
      expect(projectDir.existsSync(), isTrue);
      expect(
        pubGetInvocations.map((d) => memoryFs.path.normalize(d.path)),
        contains(memoryFs.path.normalize(projectDir.path)),
      );
      expect(logger.infos, contains('Dependencies installed successfully.'));
      expect(logger.infos.contains('  dart pub get'), isFalse);

      final pubspecFile = memoryFs.file(
        memoryFs.path.join(projectDir.path, 'pubspec.yaml'),
      );
      final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      expect(pubspec['name'], equals('demo_app'));
      final dependencies = pubspec['dependencies'] as YamlMap;
      expect(dependencies.containsKey('routed'), isTrue);

      expect(_exists(projectDir, 'config'), isFalse);
      expect(_exists(projectDir, 'lib/config.dart'), isTrue);

      expect(_exists(projectDir, 'analysis_options.yaml'), isTrue);
      expect(_exists(projectDir, 'README.md'), isTrue);

      final serverContent = _read(projectDir, 'bin/server.dart');
      expect(
        serverContent,
        contains("import 'package:demo_app/app.dart' as app;"),
      );
      expect(serverContent, contains("import 'package:routed/routed.dart';"));
      expect(
        serverContent,
        contains('final Engine engine = await app.createEngine();'),
      );

      final appContent = _read(projectDir, 'lib/app.dart');
      expect(
        appContent,
        contains('Future<Engine> createEngine({bool initialize = true}) async'),
      );
      expect(appContent, contains("import 'config.dart';"));
      expect(appContent, contains('final setup = config();'));
      expect(appContent, contains('Welcome to Demo App!'));

      final configContent = _read(projectDir, 'lib/config.dart');
      expect(configContent, contains('final class AppConfig'));
      expect(configContent, contains('AppConfig config()'));
      expect(configContent, contains('CoreServiceProvider()'));

      final manifestScript = _read(projectDir, 'tool/spec_manifest.dart');
      expect(manifestScript, contains('buildRouteManifest'));

      expect(_exists(projectDir, '.gitignore'), isTrue);
      expect(_read(projectDir, '.gitignore'), contains('.dart_tool/'));
      expect(_exists(projectDir, '.env'), isFalse);
      expect(_exists(projectDir, '.env.example'), isFalse);

      expect(_exists(projectDir, 'lib/commands.dart'), isTrue);
      expect(
        _read(projectDir, 'lib/commands.dart'),
        contains('buildProjectCommands'),
      );
    });

    test('uses output directory when provided', () async {
      final outputPath = memoryFs.path.join(workspace.path, 'sandbox');
      await _run(runner, ['create', '--output', outputPath]);

      final projectDir = memoryFs.directory(outputPath);
      expect(projectDir.existsSync(), isTrue);
      expect(
        pubGetInvocations.map((d) => memoryFs.path.normalize(d.path)),
        contains(memoryFs.path.normalize(projectDir.path)),
      );
    });

    test('warns when dart pub get fails', () async {
      pubGetExitCode = 65;
      await _run(runner, ['create', '--name', 'oops_app']);

      expect(pubGetInvocations, isNotEmpty);
      expect(
        logger.warnings.any(
          (message) => message.contains('dart pub get exited with code 65'),
        ),
        isTrue,
      );
      expect(logger.infos.contains('  dart pub get'), isTrue);
    });

    test('exposes template names in usage', () {
      final command = runner.commands['create'] as CreateCommand;
      expect(command.usage, contains('basic, api, web, fullstack'));
    });

    test('scaffolds API template with tests', () async {
      await _run(runner, ['create', '--name', 'demo_api', '--template', 'api']);

      final projectDir = memoryFs.directory(
        memoryFs.path.join(workspace.path, 'demo_api'),
      );
      final appContent = _read(projectDir, 'lib/app.dart');
      expect(appContent, contains("'/api/v1'"));
      expect(appContent, contains("router.get('/users'"));
      expect(appContent, contains('ctx.fetchOr404'));
      expect(_exists(projectDir, 'test/api_test.dart'), isTrue);

      final pubspec = loadYaml(_read(projectDir, 'pubspec.yaml')) as YamlMap;
      final devDeps = pubspec['dev_dependencies'] as YamlMap? ?? YamlMap();
      expect(devDeps.containsKey('routed_testing'), isTrue);
      expect(devDeps['routed_testing'], equals('>=0.4.0 <1.0.0'));
    });

    test('scaffolds web template with HTML helpers', () async {
      await _run(runner, ['create', '--name', 'demo_web', '--template', 'web']);

      final projectDir = memoryFs.directory(
        memoryFs.path.join(workspace.path, 'demo_web'),
      );
      final appContent = _read(projectDir, 'lib/app.dart');
      expect(appContent, contains('LiquidViewEngine'));
      expect(appContent, contains("engine.static('/assets'"));
      expect(appContent, contains("templateName: 'home.liquid'"));
      expect(appContent, contains('ctx.template'));
      expect(appContent, contains('ctx.requireFound'));
      expect(_exists(projectDir, 'templates/home.liquid'), isTrue);
      expect(_exists(projectDir, 'templates/page.liquid'), isTrue);
      expect(_exists(projectDir, 'public/styles.css'), isTrue);
      final homeTemplate = _read(projectDir, 'templates/home.liquid');
      expect(homeTemplate, contains('{{ app_title }}'));
      expect(homeTemplate, contains('cdn.tailwindcss.com'));
    });

    test('scaffolds fullstack template with API and HTML', () async {
      await _run(runner, [
        'create',
        '--name',
        'demo_full',
        '--template',
        'fullstack',
      ]);

      final projectDir = memoryFs.directory(
        memoryFs.path.join(workspace.path, 'demo_full'),
      );
      final appContent = _read(projectDir, 'lib/app.dart');
      expect(appContent, contains("'/api'"));
      expect(appContent, contains('ctx.template'));
      expect(_exists(projectDir, 'templates/todos.liquid'), isTrue);
      expect(_exists(projectDir, 'test/api_test.dart'), isTrue);

      final pubspec = loadYaml(_read(projectDir, 'pubspec.yaml')) as YamlMap;
      final devDeps = pubspec['dev_dependencies'] as YamlMap? ?? YamlMap();
      expect(devDeps.containsKey('routed_testing'), isTrue);
      expect(devDeps['routed_testing'], equals('>=0.4.0 <1.0.0'));
    });

    test('supports all template options', () async {
      const templates = <String, _TemplateExpectation>{
        'basic': _TemplateExpectation(
          expectedFiles: ['lib/app.dart', 'lib/config.dart'],
          contentChecks: {'lib/app.dart': 'Welcome to'},
        ),
        'api': _TemplateExpectation(
          expectedFiles: ['test/api_test.dart', 'lib/config.dart'],
          contentChecks: {'lib/app.dart': "router.get('/users'"},
        ),
        'web': _TemplateExpectation(
          expectedFiles: ['templates/home.liquid', 'lib/config.dart'],
          contentChecks: {'templates/home.liquid': 'cdn.tailwindcss.com'},
        ),
        'fullstack': _TemplateExpectation(
          expectedFiles: ['templates/todos.liquid', 'lib/config.dart'],
          contentChecks: {'lib/app.dart': "templateName: 'todos.liquid'"},
        ),
      };

      for (final entry in templates.entries) {
        final name = 'demo_${entry.key}';
        await _run(runner, ['create', '--name', name, '--template', entry.key]);

        final projectDir = memoryFs.directory(
          memoryFs.path.join(workspace.path, name),
        );
        expect(projectDir.existsSync(), isTrue);

        for (final path in entry.value.expectedFiles) {
          expect(_exists(projectDir, path), isTrue);
        }
        for (final check in entry.value.contentChecks.entries) {
          expect(_read(projectDir, check.key), contains(check.value));
        }
      }
    });

    test('fails fast when template is unknown', () async {
      await _expectUsageError(runner, [
        'create',
        '--template',
        'unknown',
      ], 'Unsupported template');
    });

    group('workspace detection', () {
      late fs.Directory workspaceRoot;

      setUp(() {
        // Create a parent directory that acts as a Dart workspace root.
        workspaceRoot = memoryFs.directory('/mono')
          ..createSync(recursive: true);
        memoryFs
            .file(memoryFs.path.join(workspaceRoot.path, 'pubspec.yaml'))
            .writeAsStringSync(
              'name: my_workspace\n'
              'publish_to: none\n'
              'workspace:\n'
              '  - packages/existing_pkg\n'
              '\n'
              'environment:\n'
              '  sdk: ">=3.9.0 <4.0.0"\n',
            );
        // Set current directory inside the workspace.
        memoryFs.currentDirectory = workspaceRoot;
      });

      test('adds resolution: workspace when inside a workspace', () async {
        runner = RoutedCommandRunner(logger: logger)
          ..register([
            CreateCommand(
              logger: logger,
              fileSystem: memoryFs,
              pubGet: (d) async {
                pubGetInvocations.add(d);
                return 0;
              },
            ),
          ]);

        await _run(runner, ['create', '--name', 'new_app']);

        final projectDir = memoryFs.directory(
          memoryFs.path.join(workspaceRoot.path, 'new_app'),
        );
        final pubspecContent = _read(projectDir, 'pubspec.yaml');
        final pubspec = loadYaml(pubspecContent) as YamlMap;
        expect(pubspec['resolution'], equals('workspace'));
      });

      test('adds project to parent workspace member list', () async {
        runner = RoutedCommandRunner(logger: logger)
          ..register([
            CreateCommand(
              logger: logger,
              fileSystem: memoryFs,
              pubGet: (d) async {
                pubGetInvocations.add(d);
                return 0;
              },
            ),
          ]);

        await _run(runner, ['create', '--name', 'new_app']);

        final rootPubspec = memoryFs
            .file(memoryFs.path.join(workspaceRoot.path, 'pubspec.yaml'))
            .readAsStringSync();
        final doc = loadYaml(rootPubspec) as YamlMap;
        final members = (doc['workspace'] as YamlList).toList();
        expect(members.map((m) => m.toString()), contains('new_app'));
        // Original member should still be present.
        expect(
          members.map((m) => m.toString()),
          contains('packages/existing_pkg'),
        );
      });

      test('logs workspace addition', () async {
        runner = RoutedCommandRunner(logger: logger)
          ..register([
            CreateCommand(
              logger: logger,
              fileSystem: memoryFs,
              pubGet: (d) async => 0,
            ),
          ]);

        await _run(runner, ['create', '--name', 'new_app']);

        expect(logger.infos, contains('Added "new_app" to workspace.'));
      });

      test(
        'does not duplicate workspace member on re-run with --force',
        () async {
          runner = RoutedCommandRunner(logger: logger)
            ..register([
              CreateCommand(
                logger: logger,
                fileSystem: memoryFs,
                pubGet: (d) async => 0,
              ),
            ]);

          await _run(runner, ['create', '--name', 'new_app']);
          await _run(runner, ['create', '--name', 'new_app', '--force']);

          final rootPubspec = memoryFs
              .file(memoryFs.path.join(workspaceRoot.path, 'pubspec.yaml'))
              .readAsStringSync();
          final doc = loadYaml(rootPubspec) as YamlMap;
          final members = (doc['workspace'] as YamlList).toList();
          final count = members.where((m) => m.toString() == 'new_app').length;
          expect(count, equals(1));
        },
      );

      test(
        'does not add resolution: workspace without parent workspace',
        () async {
          // Reset to the original workspace directory which has no workspace root.
          memoryFs.currentDirectory = workspace;
          runner = RoutedCommandRunner(logger: logger)
            ..register([
              CreateCommand(
                logger: logger,
                fileSystem: memoryFs,
                pubGet: (d) async => 0,
              ),
            ]);

          await _run(runner, ['create', '--name', 'standalone_app']);

          final projectDir = memoryFs.directory(
            memoryFs.path.join(workspace.path, 'standalone_app'),
          );
          final pubspecContent = _read(projectDir, 'pubspec.yaml');
          expect(pubspecContent, isNot(contains('resolution: workspace')));
        },
      );
    });
  });
}

class _TemplateExpectation {
  const _TemplateExpectation({
    required this.expectedFiles,
    required this.contentChecks,
  });

  final List<String> expectedFiles;
  final Map<String, String> contentChecks;
}

Future<void> _run(RoutedCommandRunner runner, List<String> args) async {
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    fail('Command failed: $e');
  }
}

Future<void> _expectUsageError(
  RoutedCommandRunner runner,
  List<String> args,
  String fragment,
) async {
  try {
    await runner.run(args);
    fail('Expected UsageException for args: $args');
  } on UsageException catch (e) {
    expect(e.message, contains(fragment));
  }
}

bool _exists(fs.Directory root, String relativePath) {
  return root.fileSystem
      .file(root.fileSystem.path.join(root.path, relativePath))
      .existsSync();
}

String _read(fs.Directory root, String relativePath) {
  return root.fileSystem
      .file(root.fileSystem.path.join(root.path, relativePath))
      .readAsStringSync();
}

class _RecordingLogger extends CliLogger {
  _RecordingLogger() : super(verbose: true);

  final List<String> infos = [];
  final List<String> warnings = [];
  final List<String> errors = [];

  @override
  void info(Object? message) {
    infos.add(message.toString());
  }

  @override
  void warn(Object? message) {
    warnings.add(message.toString());
  }

  @override
  void error(Object? message) {
    errors.add(message.toString());
  }

  @override
  void debug(Object? message) {
    infos.add('DEBUG: ${message.toString()}');
  }
}
