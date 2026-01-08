import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;

import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/commands/create.dart';
import 'package:routed/src/console/args/runner.dart';
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

      final projectDir = memoryFs.directory(p.join(workspace.path, 'demo_app'));
      expect(projectDir.existsSync(), isTrue);
      expect(
        pubGetInvocations.map((d) => p.normalize(d.path)),
        contains(p.normalize(projectDir.path)),
      );
      expect(logger.infos, contains('Dependencies installed successfully.'));
      expect(logger.infos.contains('  dart pub get'), isFalse);

      final pubspecFile = memoryFs.file(
        p.join(projectDir.path, 'pubspec.yaml'),
      );
      final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      expect(pubspec['name'], equals('demo_app'));
      final dependencies = pubspec['dependencies'] as YamlMap;
      expect(dependencies.containsKey('routed'), isTrue);

      expect(_exists(projectDir, 'config/http.yaml'), isTrue);
      expect(_read(projectDir, 'config/http.yaml'), contains('providers:'));

      final cacheContent = _read(projectDir, 'config/cache.yaml');
      expect(cacheContent, contains('default: file'));
      expect(cacheContent, contains('# Cache configuration quick reference:'));
      expect(cacheContent, contains('Name of the cache store'));

      final sessionContent = _read(projectDir, 'config/session.yaml');
      expect(
        sessionContent,
        contains(
          "cookie: \"{{ env.SESSION_COOKIE | default: 'routed-session' }}\"",
        ),
      );
      expect(
        sessionContent,
        contains('# Session configuration quick reference:'),
      );
      expect(sessionContent, contains('same_site'));

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
      expect(appContent, contains('Future<Engine> createEngine() async'));
      expect(appContent, contains('Welcome to Demo App!'));

      final manifestScript = _read(projectDir, 'tool/spec_manifest.dart');
      expect(manifestScript, contains('buildRouteManifest'));

      final loggingConfig = _read(projectDir, 'config/logging.yaml');
      expect(
        loggingConfig,
        contains('# Logging configuration quick reference:'),
      );

      final storageContent = _read(projectDir, 'config/storage.yaml');
      expect(
        storageContent,
        contains('# Storage configuration quick reference:'),
      );
      expect(
        storageContent,
        contains("root: \"{{ env.STORAGE_ROOT | default: 'storage/app' }}\""),
      );
      expect(storageContent, contains('default:'));

      final staticConfig = _read(projectDir, 'config/static.yaml');
      expect(staticConfig, contains('# Static configuration quick reference:'));

      final uploadsConfig = _read(projectDir, 'config/uploads.yaml');
      expect(
        uploadsConfig,
        contains('# Uploads configuration quick reference:'),
      );

      final securityConfig = _read(projectDir, 'config/security.yaml');
      expect(
        securityConfig,
        contains('# Security configuration quick reference:'),
      );

      expect(_exists(projectDir, '.gitignore'), isTrue);
      expect(_read(projectDir, '.gitignore'), contains('.dart_tool/'));

      final envContent = _read(projectDir, '.env');
      expect(envContent, isNot(contains('change-me')));
      expect(envContent, contains('SESSION_COOKIE=demo_app_session'));
      expect(envContent, contains('STORAGE_ROOT=storage/app'));

      final envKeyLine = envContent
          .split('\n')
          .firstWhere((line) => line.startsWith('APP_KEY='));
      final envKey = envKeyLine.substring('APP_KEY='.length);
      expect(envKey, isNotEmpty);
      expect(envKey, matches(RegExp(r'^[A-Za-z0-9+/=]+$')));

      final envExample = _read(projectDir, '.env.example');
      expect(envExample, contains('APP_KEY=$envKey'));

      final appConfig = _read(projectDir, 'config/app.yaml');
      expect(
        appConfig,
        contains("key: \"{{ env.APP_KEY | default: 'change-me' }}\""),
      );
      expect(appConfig, isNot(contains(envKey)));

      expect(_exists(projectDir, 'lib/commands.dart'), isTrue);
      expect(
        _read(projectDir, 'lib/commands.dart'),
        contains('buildProjectCommands'),
      );
    });

    test('uses output directory when provided', () async {
      final outputPath = p.join(workspace.path, 'sandbox');
      await _run(runner, ['create', '--output', outputPath]);

      final projectDir = memoryFs.directory(outputPath);
      expect(projectDir.existsSync(), isTrue);
      expect(
        pubGetInvocations.map((d) => p.normalize(d.path)),
        contains(p.normalize(projectDir.path)),
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

      final projectDir = memoryFs.directory(p.join(workspace.path, 'demo_api'));
      final appContent = _read(projectDir, 'lib/app.dart');
      expect(appContent, contains("'/api/v1'"));
      expect(appContent, contains("router.get('/users'"));
      expect(appContent, contains('ctx.fetchOr404'));
      expect(_exists(projectDir, 'test/api_test.dart'), isTrue);

      final pubspec = loadYaml(_read(projectDir, 'pubspec.yaml')) as YamlMap;
      final devDeps = pubspec['dev_dependencies'] as YamlMap? ?? YamlMap();
      expect(devDeps.containsKey('routed_testing'), isTrue);
    });

    test('scaffolds web template with HTML helpers', () async {
      await _run(runner, ['create', '--name', 'demo_web', '--template', 'web']);

      final projectDir = memoryFs.directory(p.join(workspace.path, 'demo_web'));
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
      expect(homeTemplate, contains('/assets/styles.css'));
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
        p.join(workspace.path, 'demo_full'),
      );
      final appContent = _read(projectDir, 'lib/app.dart');
      expect(appContent, contains("'/api'"));
      expect(appContent, contains('ctx.html'));
      expect(_exists(projectDir, 'test/api_test.dart'), isTrue);

      final pubspec = loadYaml(_read(projectDir, 'pubspec.yaml')) as YamlMap;
      final devDeps = pubspec['dev_dependencies'] as YamlMap? ?? YamlMap();
      expect(devDeps.containsKey('routed_testing'), isTrue);
    });

    test('fails fast when template is unknown', () async {
      await _expectUsageError(runner, [
        'create',
        '--template',
        'unknown',
      ], 'Unsupported template');
    });
  });
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
  return root.fileSystem.file(p.join(root.path, relativePath)).existsSync();
}

String _read(fs.Directory root, String relativePath) {
  return root.fileSystem
      .file(p.join(root.path, relativePath))
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
