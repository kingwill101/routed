import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/providers.dart'
    show ProviderRegistry, SessionServiceProvider;
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/args/commands/provider.dart';
import 'package:routed_cli/src/args/commands/provider_driver.dart';
import 'package:routed_cli/src/args/runner.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

@Tags(['serial'])
void main() {
  group('Provider commands', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;

    setUp(() async {
      memoryFs = MemoryFileSystem();
      projectRoot = memoryFs.directory('/workspace/project')
        ..createSync(recursive: true);
      memoryFs.currentDirectory = projectRoot;

      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          _TestProviderListCommand(() => projectRoot, logger, memoryFs),
          _TestProviderEnableCommand(() => projectRoot, logger, memoryFs),
          _TestProviderDisableCommand(() => projectRoot, logger, memoryFs),
          _TestProviderDriverCommand(() => projectRoot, logger, memoryFs),
        ]);

      await _writeFile(projectRoot, 'pubspec.yaml', 'name: demo\n');
      await _writeFile(
        projectRoot,
        'config/http.yaml',
        'providers:\n  - routed.core\n  - routed.routing\nfeatures:\n  routing:\n    enabled: true\n  sessions:\n    enabled: false\n',
      );
    });

    String read(String relativePath) => memoryFs
        .file(p.join(projectRoot.path, relativePath))
        .readAsStringSync();

    bool exists(String relativePath) =>
        memoryFs.file(p.join(projectRoot.path, relativePath)).existsSync();

    test('provider:enable appends provider to manifest', () async {
      await _run(runner, ['provider:enable', 'routed.sessions']);

      final contents = read('config/http.yaml');
      expect(contents, contains('routed.sessions'));
      final yaml = loadYaml(contents) as YamlMap;
      final features = yaml['features'] as YamlMap;
      expect((features['sessions'] as YamlMap)['enabled'], isTrue);
    });

    test('provider:disable removes provider from manifest', () async {
      await _run(runner, ['provider:disable', 'routed.routing']);

      final contents = read('config/http.yaml');
      expect(contents, isNot(contains('routed.routing')));
      final yaml = loadYaml(contents) as YamlMap;
      final features = yaml['features'] as YamlMap;
      expect((features['routing'] as YamlMap)['enabled'], isFalse);
    });

    test('provider:list --config prints defaults', () async {
      await _run(runner, ['provider:list', '--config']);
      final output = logger.infos.join('\n');
      expect(output, contains('routed.core'));
      expect(output, contains('defaults:'));
      expect(output, contains('http:'));
      expect(output, contains('storage.disks.*.file_system'));
      expect(output, contains('session.same_site'));
      expect(output, contains('options=[lax, strict, none]'));
    });

    test('provider:list surfaces duplicate driver errors', () async {
      final registry = ProviderRegistry.instance;
      final original = registry.resolve('routed.sessions')!;
      final originalFactory = original.factory;
      final originalDescription = original.description;

      registry.register(
        'routed.sessions',
        factory: () => _DuplicateDriverProvider(),
        description: originalDescription,
      );
      addTearDown(() {
        registry.register(
          'routed.sessions',
          factory: originalFactory,
          description: originalDescription,
        );
      });

      await expectLater(
        () async => runner.run(['provider:list', '--config']),
        throwsA(
          isA<UsageException>()
              .having(
                (e) => e.message,
                'message',
                contains('Duplicate driver registration'),
              )
              .having((e) => e.message, 'message', contains('cookie')),
        ),
      );
    });

    test('provider:driver scaffolds storage driver starter', () async {
      await _run(runner, ['provider:driver', 'storage', 'dropbox']);

      final driverPath = 'lib/drivers/storage/dropbox_storage_driver.dart';
      expect(exists(driverPath), isTrue);
      final contents = read(driverPath);
      expect(contents, contains('registerDropboxStorageDriver'));
      expect(contents, contains('StorageServiceProvider.registerDriver'));
    });

    test('provider:driver scaffolds cache driver starter', () async {
      await _run(runner, ['provider:driver', '--type', 'cache', 'memcached']);

      final driverPath = 'lib/drivers/cache/memcached_cache_driver.dart';
      expect(exists(driverPath), isTrue);
      final contents = read(driverPath);
      expect(contents, contains('registerMemcachedCacheDriver'));
      expect(contents, contains('CacheManager.registerDriver'));
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
  fs.Directory root,
  String relativePath,
  String contents,
) async {
  final file = root.fileSystem.file(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

class _TestProviderListCommand extends ProviderListCommand {
  _TestProviderListCommand(
    this._rootProvider,
    rc.CliLogger logger,
    MemoryFileSystem fs,
  ) : _fs = fs,
      super(logger: logger, fileSystem: fs);

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

class _TestProviderEnableCommand extends ProviderEnableCommand {
  _TestProviderEnableCommand(
    this._rootProvider,
    rc.CliLogger logger,
    MemoryFileSystem fs,
  ) : _fs = fs,
      super(logger: logger, fileSystem: fs);

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

class _TestProviderDisableCommand extends ProviderDisableCommand {
  _TestProviderDisableCommand(
    this._rootProvider,
    rc.CliLogger logger,
    MemoryFileSystem fs,
  ) : _fs = fs,
      super(logger: logger, fileSystem: fs);

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

class _TestProviderDriverCommand extends ProviderDriverCommand {
  _TestProviderDriverCommand(
    this._rootProvider,
    rc.CliLogger logger,
    MemoryFileSystem fs,
  ) : _fs = fs,
      super(logger: logger, fileSystem: fs);

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

class _DuplicateDriverProvider extends ServiceProvider {
  _DuplicateDriverProvider() {
    SessionServiceProvider.registerDriver(
      'cookie',
      (context) => SessionConfig.cookie(
        appKey: SecureCookie.generateKey(),
        codecs: context.codecs,
        cookieName: context.cookieName,
        maxAge: context.lifetime,
        expireOnClose: context.expireOnClose,
        options: context.options,
      ),
    );
  }

  @override
  void register(Container container) {}

  @override
  Future<void> cleanup(Container container) async {}
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
