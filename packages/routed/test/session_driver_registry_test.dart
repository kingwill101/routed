import 'dart:convert';

import 'package:file/memory.dart';
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart' show EngineConfig, SessionConfig;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/engine/providers/sessions.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/sessions/cache_store.dart';
import 'package:routed/src/sessions/filesystem_store.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    // Ensure built-in drivers are registered.
    SessionServiceProvider.availableDriverNames(includeBuiltIns: true);
    CacheManager.registeredDrivers;
  });

  group('Session file driver', () {
    test('uses StorageDefaults when available', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-defaults-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = fs.path.join(baseDir.path, 'storage', 'app');
      fs.directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);

      final container = Container()
        ..instance<MiddlewareRegistry>(MiddlewareRegistry())
        ..instance<EngineConfig>(EngineConfig(fileSystem: fs))
        ..instance<StorageDefaults>(storageDefaults);

      final config = ConfigImpl({
        'app': {
          'key':
              'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
        },
        'session': {'enabled': true, 'driver': 'file'},
      });
      container.instance<Config>(config);

      final provider = SessionServiceProvider();
      provider.register(container);

      final sessionConfig = container.get<SessionConfig>();
      final store = sessionConfig.store;

      expect(store, isA<FilesystemStore>());
      final pathContext = fs.path;
      expect(
        pathContext.normalize((store as FilesystemStore).storageDir),
        equals(
          pathContext.normalize(storageDefaults.frameworkPath('sessions')),
        ),
      );
    });

    test('falls back to Config when StorageDefaults missing', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-config-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = fs.path.join(baseDir.path, 'storage', 'app');
      fs.directory(localRoot).createSync(recursive: true);

      final container = Container()
        ..instance<MiddlewareRegistry>(MiddlewareRegistry())
        ..instance<EngineConfig>(EngineConfig(fileSystem: fs));

      final config = ConfigImpl({
        'app': {
          'key':
              'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
        },
        'storage': {
          'disks': {
            'local': {'root': localRoot},
          },
        },
        'session': {'enabled': true, 'driver': 'file'},
      });
      container.instance<Config>(config);

      final provider = SessionServiceProvider();
      provider.register(container);

      final sessionConfig = container.get<SessionConfig>();
      final store = sessionConfig.store;

      expect(store, isA<FilesystemStore>());
      final pathContext = fs.path;
      expect(
        pathContext.normalize((store as FilesystemStore).storageDir),
        equals(
          pathContext.normalize(
            resolveFrameworkStoragePath(config, child: 'sessions'),
          ),
        ),
      );
    });

    test('normalizes user-provided paths with StorageDefaults', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-custom-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = fs.path.join(baseDir.path, 'storage', 'app');
      fs.directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);

      final container = Container()
        ..instance<MiddlewareRegistry>(MiddlewareRegistry())
        ..instance<EngineConfig>(EngineConfig(fileSystem: fs))
        ..instance<StorageDefaults>(storageDefaults);

      final config = ConfigImpl({
        'app': {
          'key':
              'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
        },
        'session': {
          'enabled': true,
          'driver': 'file',
          'files': 'sessions/custom',
        },
      });
      container.instance<Config>(config);

      final provider = SessionServiceProvider();
      provider.register(container);

      final sessionConfig = container.get<SessionConfig>();
      final store = sessionConfig.store;

      expect(store, isA<FilesystemStore>());
      final pathContext = fs.path;
      expect(
        pathContext.normalize((store as FilesystemStore).storageDir),
        equals(
          pathContext.normalize(storageDefaults.resolve('sessions/custom')),
        ),
      );
    });
  });

  group('Cache-backed session driver', () {
    CacheManager createCacheManager() {
      final manager = CacheManager();
      manager.registerStore('existing', {'driver': 'array'});
      return manager;
    }

    Container createBaseContainer() {
      final container = Container()
        ..instance<MiddlewareRegistry>(MiddlewareRegistry());
      return container;
    }

    ConfigImpl baseConfig(Map<String, dynamic> sessionOverrides) {
      final sessionConfig = {
        'enabled': true,
        'driver': 'cache',
        ...sessionOverrides,
      };
      return ConfigImpl({
        'app': {
          'key':
              'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
        },
        'session': sessionConfig,
      });
    }

    test('reports missing store with available names', () {
      final container = createBaseContainer()
        ..instance<CacheManager>(createCacheManager());

      final config = baseConfig({'store': 'missing-store'});
      container.instance<Config>(config);

      final provider = SessionServiceProvider();

      expect(
        () => provider.register(container),
        throwsA(
          isA<ProviderConfigException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Session cache store [missing-store] is not defined'),
              contains('Available stores: existing'),
            ),
          ),
        ),
      );
    });

    test('resolves when referenced cache store exists', () {
      final cacheManager = createCacheManager();
      final container = createBaseContainer()
        ..instance<CacheManager>(cacheManager);

      final config = baseConfig({'store': 'existing'});
      container.instance<Config>(config);

      final provider = SessionServiceProvider();
      provider.register(container);

      final sessionConfig = container.get<SessionConfig>();
      expect(sessionConfig.store, isA<CacheSessionStore>());
    });
  });
}
