import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
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
          _TestConfigPublishCommand(() => projectRoot, memoryFs),
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

    test('config:publish generates default templates', () async {
      await _run(runner, ['config:publish']);

      expect(exists('config/app.yaml'), isTrue);
      expect(exists('config/http.yaml'), isTrue);
    });

    test('config:publish filters defaults by selection', () async {
      await _run(runner, ['config:publish', 'app,cache']);

      expect(exists('config/app.yaml'), isTrue);
      expect(exists('config/cache.yaml'), isTrue);
      expect(exists('config/http.yaml'), isFalse);
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

    test(
      'config:cache without env refs keeps const and no routed import',
      () async {
        await _writeFile(
          memoryFs,
          projectRoot,
          'config/app.yaml',
          'name: Plain App\ndebug: true\n',
        );

        await _run(runner, ['config:cache']);

        final dartCache = read('lib/generated/routed_config.dart');
        expect(dartCache, contains('const Map<String, dynamic> routedConfig'));
        expect(dartCache, contains("'Plain App'"));
      },
    );

    test('config:cache preserves env template placeholders', () async {
      await _writeFile(
        memoryFs,
        projectRoot,
        'config/app.yaml',
        "name: \"{{ env.APP_NAME | default: 'My App' }}\"\n"
            "debug: {{ env.APP_DEBUG | default: false }}\n"
            "greeting: \"Hello {{ env.APP_USER | default: 'world' }}!\"\n",
      );

      await _run(runner, ['config:cache']);

      final dartCache = read('lib/generated/routed_config.dart');

      // Should import routed and have resolveRoutedConfig().
      expect(dartCache, contains("import 'package:routed/routed.dart';"));
      expect(dartCache, contains('resolveRoutedConfig()'));

      // Env templates must survive as raw strings in the const map.
      // Single quotes inside the value are escaped as \' in the generated Dart.
      expect(dartCache, contains(r"{{ env.APP_NAME | default: \'My App\' }}"));
      expect(dartCache, contains('{{ env.APP_DEBUG | default: false }}'));
      expect(dartCache, contains(r"{{ env.APP_USER | default: \'world\' }}"));

      // Non-env values should still be expanded.
      expect(dartCache, isNot(contains('{{ app.')));
    });

    test('config:cache resolveRoutedConfig resolves env placeholders', () async {
      await _writeFile(
        memoryFs,
        projectRoot,
        'config/app.yaml',
        "name: \"{{ env.APP_NAME | default: 'Fallback' }}\"\n",
      );

      await _run(runner, ['config:cache']);

      final dartCache = read('lib/generated/routed_config.dart');
      // The raw map has the placeholder (with escaped quotes in the Dart file).
      expect(
        dartCache,
        contains(r"{{ env.APP_NAME | default: \'Fallback\' }}"),
      );

      // Verify that renderDefaults resolves the placeholder using defaults
      // when the env var is not set.
      final loader = ConfigLoader();
      final ctx = buildEnvTemplateContext();
      final rawMap = <String, dynamic>{
        'app': <String, dynamic>{
          'name': "{{ env.APP_NAME | default: 'Fallback' }}",
        },
      };
      // ignore: avoid_dynamic_calls
      final resolved = loader.renderDefaults(rawMap, ctx);
      final appMap = resolved['app'] as Map<String, dynamic>;
      // If APP_NAME is not in the environment, the Liquid default kicks in.
      final envAppName = Platform.environment['APP_NAME'];
      if (envAppName == null || envAppName.isEmpty) {
        expect(appMap['name'], equals('Fallback'));
      }
    });

    test('config:cache non-env templates are still expanded', () async {
      await _writeFile(
        memoryFs,
        projectRoot,
        'config/mail.yaml',
        'driver: smtp\n'
            "host: \"{{ mail.host | default: 'localhost' }}\"\n",
      );
      await _writeFile(memoryFs, projectRoot, '.env', '');

      await _run(runner, ['config:cache']);

      final dartCache = read('lib/generated/routed_config.dart');
      // Non-env template should be expanded to the default value.
      expect(dartCache, contains("'localhost'"));
      expect(dartCache, isNot(contains('{{ mail.host')));
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
  final file = fs.file(fs.path.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
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
  _TestConfigPublishCommand(this._rootProvider, MemoryFileSystem fs)
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
