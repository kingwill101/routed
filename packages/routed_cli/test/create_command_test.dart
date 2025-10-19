import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/args/commands/create.dart';
import 'package:routed_cli/src/args/runner.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

@Tags(['serial'])
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
      expect(cacheContent, contains('default: array'));
      expect(cacheContent, contains('# Cache configuration quick reference:'));
      expect(cacheContent, contains('Options: array, file, null'));

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
      expect(sessionContent, contains('Options: array, cache, cookie'));

      expect(_exists(projectDir, 'analysis_options.yaml'), isTrue);
      expect(_exists(projectDir, 'README.md'), isTrue);

      final serverContent = _read(projectDir, 'bin/server.dart');
      expect(
        serverContent,
        contains("import 'package:demo_app/app.dart' as app;"),
      );
      expect(serverContent, contains('await app.createEngine()'));

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
      expect(storageContent, contains('Options: local'));

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
  });
}

Future<void> _run(RoutedCommandRunner runner, List<String> args) async {
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    fail('Command failed: $e');
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

class _RecordingLogger extends rc.CliLogger {
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
