import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/src/console/args/commands/config.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:test/test.dart';

void main() {
  group('Config commands', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;

    setUp(() async {
      memoryFs = MemoryFileSystem();
      projectRoot = memoryFs.directory('/workspace/project')
        ..createSync(recursive: true);
      memoryFs.currentDirectory = projectRoot;

      runner = RoutedCommandRunner()
        ..register([
          _TestConfigInitCommand(() => projectRoot, memoryFs),
          _TestConfigPublishCommand(
            () => projectRoot,
            () => memoryFs.directory('/workspace/vendor/mailer_pkg'),
            memoryFs,
          ),
          _TestConfigCacheCommand(() => projectRoot, memoryFs),
          _TestConfigClearCommand(() => projectRoot, memoryFs),
        ]);

      await _writeFile(memoryFs, projectRoot, 'pubspec.yaml', 'name: demo\n');
    });

    String read(String relativePath) => memoryFs
        .file(memoryFs.path.join(projectRoot.path, relativePath))
        .readAsStringSync();

    bool exists(String relativePath) => memoryFs
        .file(memoryFs.path.join(projectRoot.path, relativePath))
        .existsSync();

    test('config:init scaffolds base templates', () async {
      await _run(runner, ['config:init']);

      expect(exists('config/app.yaml'), isTrue);
      expect(exists('config/http.yaml'), isTrue);
      expect(exists('.env'), isTrue);

      final appYaml = read('config/app.yaml');
      expect(
        appYaml,
        contains("name: \"{{ env.APP_NAME | default: 'Routed App' }}\""),
      );

      expect(
        read('config/session.yaml'),
        contains('# Session configuration quick reference:'),
      );
      expect(
        read('config/cache.yaml'),
        contains('# Cache configuration quick reference:'),
      );
      final cacheYaml = read('config/cache.yaml');
      expect(
        cacheYaml,
        contains(
          'Default: {"array":{"driver":"array"},"file":{"driver":"file","path":"storage/framework/cache"}}.',
        ),
      );
      expect(
        cacheYaml,
        contains('Validation: Must resolve to a non-empty directory path.'),
      );
      expect(
        read('config/storage.yaml'),
        contains('# Storage configuration quick reference:'),
      );
      final storageYaml = read('config/storage.yaml');
      expect(
        storageYaml,
        contains("root: \"{{ env.STORAGE_ROOT | default: 'storage/app' }}\""),
      );
      expect(
        read('config/uploads.yaml'),
        contains('# Uploads configuration quick reference:'),
      );
      expect(
        read('config/logging.yaml'),
        contains('# Logging configuration quick reference:'),
      );
      final sessionYaml = read('config/session.yaml');
      expect(sessionYaml, contains('Default: storage/framework/sessions.'));
      expect(
        sessionYaml,
        contains('Validation: Must match a configured cache store name.'),
      );

      final env = read('.env');
      expect(env, contains('APP_NAME=Routed App'));
      expect(env, contains('APP_ENV=development'));
      expect(env, contains('APP_DEBUG=true'));
      expect(env, contains('APP_KEY=change-me'));
      expect(env, contains('SESSION_COOKIE=routed-session'));
      expect(env, contains('STORAGE_ROOT=storage/app'));
      expect(env, contains('SESSION_DRIVER=cookie'));
      expect(env, contains('CACHE_STORE=file'));
      expect(
        env,
        contains('OBSERVABILITY_TRACING_SERVICE_NAME=routed-service'),
      );
    });

    test('config:publish copies package stubs', () async {
      final pkgRoot = memoryFs.directory('/workspace/vendor/mailer_pkg')
        ..createSync(recursive: true);
      await _writeFile(
        memoryFs,
        pkgRoot,
        p.join('config', 'stubs', 'mail.yaml'),
        'driver: smtp\n',
      );

      await _writePackageConfig(
        memoryFs,
        projectRoot,
        packages: [
          {
            'name': 'mailer_pkg',
            'rootUri': '../vendor/mailer_pkg/',
            'packageUri': 'lib/',
          },
        ],
      );

      await _run(runner, ['config:publish', 'mailer_pkg']);

      expect(exists('config/mail.yaml'), isTrue);
      expect(read('config/mail.yaml'), contains('driver: smtp'));
    });

    test('config:cache generates cache artifacts', () async {
      await _writeFile(
        memoryFs,
        projectRoot,
        'config/app.yaml',
        'name: Example App\ndebug: false\n',
      );
      await _writeFile(memoryFs, projectRoot, '.env', 'APP__ENV=testing\n');

      await _run(runner, ['config:cache']);

      final dartCache = read('lib/generated/routed_config.dart');
      expect(dartCache, contains("'Example App'"));
      expect(dartCache, contains('routedConfigEnvironment'));
      expect(dartCache, contains("'testing'"));

      final jsonCache =
          jsonDecode(read('.dart_tool/routed/config_cache.json'))
              as Map<String, dynamic>;
      expect(jsonCache['app'], containsPair('name', 'Example App'));
    });

    test('config:clear removes cache artifacts', () async {
      await _writeFile(
        memoryFs,
        projectRoot,
        'config/app.yaml',
        'name: Example App\n',
      );
      await _writeFile(memoryFs, projectRoot, '.env', 'APP__ENV=testing\n');

      await _run(runner, ['config:cache']);
      await _run(runner, ['config:clear']);

      expect(exists('lib/generated/routed_config.dart'), isFalse);
      expect(exists('.dart_tool/routed/config_cache.json'), isFalse);
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

Future<void> _writeFile(
  MemoryFileSystem fs,
  fs.Directory root,
  String relativePath,
  String contents,
) async {
  final file = fs.file(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

Future<void> _writePackageConfig(
  MemoryFileSystem fs,
  fs.Directory root, {
  required List<Map<String, dynamic>> packages,
}) async {
  final file = fs.file(p.join(root.path, '.dart_tool', 'package_config.json'));
  await file.parent.create(recursive: true);
  final data = <String, dynamic>{'configVersion': 2, 'packages': packages};
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

class _TestConfigInitCommand extends ConfigInitCommand {
  _TestConfigInitCommand(this._rootProvider, MemoryFileSystem fs)
    : _fs = fs,
      super(fileSystem: fs);

  final fs.Directory Function() _rootProvider;
  final MemoryFileSystem _fs;

  @override
  Future<fs.Directory?> findProjectRoot({
    fs.Directory? start,
    int maxLevels = 10,
  }) async {
    return _fs.directory(_rootProvider().path);
  }
}

class _TestConfigPublishCommand extends ConfigPublishCommand {
  _TestConfigPublishCommand(
    this._rootProvider,
    this.packageRootProvider,
    MemoryFileSystem fs,
  ) : _fs = fs,
      super(
        fileSystem: fs,
        packageResolver: (root, name) async => packageRootProvider(),
      );

  final fs.Directory Function() _rootProvider;
  final fs.Directory Function() packageRootProvider;
  final MemoryFileSystem _fs;

  @override
  Future<fs.Directory?> findProjectRoot({
    fs.Directory? start,
    int maxLevels = 10,
  }) async {
    return _fs.directory(_rootProvider().path);
  }
}

class _TestConfigCacheCommand extends ConfigCacheCommand {
  _TestConfigCacheCommand(this._rootProvider, MemoryFileSystem fs)
    : _fs = fs,
      super(fileSystem: fs);

  final fs.Directory Function() _rootProvider;
  final MemoryFileSystem _fs;

  @override
  Future<fs.Directory?> findProjectRoot({
    fs.Directory? start,
    int maxLevels = 10,
  }) async {
    return _fs.directory(_rootProvider().path);
  }
}

class _TestConfigClearCommand extends ConfigClearCommand {
  _TestConfigClearCommand(this._rootProvider, MemoryFileSystem fs)
    : _fs = fs,
      super(fileSystem: fs);

  final fs.Directory Function() _rootProvider;
  final MemoryFileSystem _fs;

  @override
  Future<fs.Directory?> findProjectRoot({
    fs.Directory? start,
    int maxLevels = 10,
  }) async {
    return _fs.directory(_rootProvider().path);
  }
}
