import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/cache/store_factory.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    // Ensure built-in drivers are registered for baseline tests.
    final _ = CacheManager.registeredDrivers;
  });

  group('DriverConfigContext', () {
    test('get returns services from container when available', () {
      final container = Container();
      container.instance<String>('value');
      final context = DriverConfigContext(
        userConfig: const {'key': 'value'},
        container: container,
        driverName: 'test',
      );

      expect(context.get<String>(), equals('value'));
      expect(context.get<int>(), isNull);
    });
  });

  group('CacheDriverRegistry.buildConfig', () {
    test('uses config builder and container access', () {
      const driver = 'config-builder-driver';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        configBuilder: (context) {
          final resolved = context.get<String>() ?? 'fallback';
          return {...context.userConfig, 'resolved': resolved};
        },
      );

      final container = Container()..instance<String>('container-value');
      final userConfig = {'driver': driver, 'foo': 'bar'};

      final built = CacheDriverRegistry.instance.buildConfig(
        driver,
        userConfig,
        container,
      );

      expect(built, isNot(same(userConfig)));
      expect(built['resolved'], equals('container-value'));
      expect(built['foo'], equals('bar'));
    });

    test('returns copy of config when builder absent', () {
      const driver = 'legacy-driver';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(driver, () => _RecordingStoreFactory());

      final container = Container();
      final userConfig = {'foo': 'bar'};

      final built = CacheDriverRegistry.instance.buildConfig(
        driver,
        userConfig,
        container,
      );

      expect(built, equals(userConfig));
      expect(identical(built, userConfig), isFalse);
    });

    test('throws when required configuration key missing', () {
      const driver = 'requires-driver';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        requiresConfig: const ['path'],
      );

      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig(
          driver,
          const {},
          container,
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('requires configuration key "path"'),
          ),
        ),
      );
    });

    test('throws when required configuration value is null', () {
      const driver = 'requires-non-null';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        requiresConfig: const ['path'],
      );

      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig(driver, const {
          'path': null,
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('requires non-null value for "path"'),
          ),
        ),
      );
    });

    test('wraps unexpected validator errors', () {
      const driver = 'validator-wrap';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        validator: (config, driverName) {
          throw StateError('boom');
        },
      );

      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig(
          driver,
          const {},
          container,
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('configuration validation failed'),
              contains('boom'),
            ),
          ),
        ),
      );
    });

    test('rethrows configuration exception from validator unchanged', () {
      const driver = 'validator-rethrow';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        validator: (config, driverName) {
          throw const ConfigurationException('custom failure');
        },
      );

      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig(
          driver,
          const {},
          container,
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            equals('custom failure'),
          ),
        ),
      );
    });

    test('throws ArgumentError when driver not registered', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig(
          'unknown-driver',
          const {},
          container,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Cache driver "unknown-driver" is not registered'),
          ),
        ),
      );
    });

    test('file driver computes default path using StorageDefaults', () {
      final baseDir = Directory.systemTemp.createTempSync(
        'routed-cache-storage-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);
      final container = Container()..instance<StorageDefaults>(storageDefaults);

      final config = CacheDriverRegistry.instance.buildConfig('file', const {
        'driver': 'file',
      }, container);

      expect(config['path'], equals(storageDefaults.frameworkPath('cache')));
    });

    test('file driver normalizes user path via StorageDefaults', () {
      final baseDir = Directory.systemTemp.createTempSync('routed-cache-path-');
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);
      final container = Container()..instance<StorageDefaults>(storageDefaults);

      final config = CacheDriverRegistry.instance.buildConfig('file', const {
        'driver': 'file',
        'path': 'custom/cache',
      }, container);

      expect(config['path'], equals(storageDefaults.resolve('custom/cache')));
    });

    test('file driver uses Config fallback when StorageDefaults missing', () {
      final baseDir = Directory.systemTemp.createTempSync(
        'routed-cache-config-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final appConfig = ConfigImpl({
        'storage': {
          'disks': {
            'local': {'root': localRoot},
          },
        },
      });
      final container = Container()..instance<Config>(appConfig);

      final config = CacheDriverRegistry.instance.buildConfig('file', const {
        'driver': 'file',
      }, container);

      expect(
        config['path'],
        equals(resolveFrameworkStoragePath(appConfig, child: 'cache')),
      );
    });

    test(
      'file driver falls back to literal path when no services available',
      () {
        final container = Container();

        final config = CacheDriverRegistry.instance.buildConfig('file', const {
          'driver': 'file',
        }, container);

        expect(config['path'], equals('storage/framework/cache'));
      },
    );

    test('file driver rejects invalid path types', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig('file', const {
          'driver': 'file',
          'path': 123,
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('requires a non-empty "path"'),
          ),
        ),
      );
    });

    test('file driver coerces permission strings to integers', () {
      final container = Container();

      final config = CacheDriverRegistry.instance.buildConfig('file', const {
        'driver': 'file',
        'path': 'relative/cache',
        'permission': '0644',
      }, container);

      expect(config['permission'], equals(int.parse('0644', radix: 8)));
    });

    test('file driver rejects invalid permission types', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig('file', const {
          'driver': 'file',
          'path': 'cache',
          'permission': [],
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('permission must be an integer or string'),
          ),
        ),
      );
    });

    test('redis driver rejects invalid port values', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig('redis', const {
          'driver': 'redis',
          'port': 'not-an-int',
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('port must be an integer value'),
          ),
        ),
      );
    });

    test('redis driver coerces numeric strings', () {
      final container = Container();

      final config = CacheDriverRegistry.instance.buildConfig('redis', const {
        'driver': 'redis',
        'port': '6380',
        'db': '5',
        'database': '7',
      }, container);

      expect(config['port'], equals(6380));
      expect(config['db'], equals(5));
      expect(config['database'], equals(7));
    });

    test('redis driver rejects non-string url values', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig('redis', const {
          'driver': 'redis',
          'url': 123,
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('url must be a string'),
          ),
        ),
      );
    });

    test('redis driver rejects malformed urls', () {
      final container = Container();

      expect(
        () => CacheDriverRegistry.instance.buildConfig('redis', const {
          'driver': 'redis',
          'url': 'redis:///missing-host',
        }, container),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('valid Redis URL'),
          ),
        ),
      );
    });
  });

  group('CacheManager integration', () {
    test('resolve applies config builder output', () {
      const driver = 'manager-driver';
      _RecordingStoreFactory? createdFactory;
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () {
          final factory = _RecordingStoreFactory();
          createdFactory = factory;
          return factory;
        },
        configBuilder: (context) => {
          ...context.userConfig,
          'computed': context.get<String>() ?? 'missing',
        },
        requiresConfig: const ['required'],
      );

      final container = Container()..instance<String>('from-container');
      final manager = CacheManager(container: container);
      manager.registerStore('custom', const {'driver': driver, 'required': 1});

      manager.store('custom');

      expect(createdFactory, isNotNull);
      expect(createdFactory!.lastConfig, isNotNull);
      final config = createdFactory!.lastConfig!;
      expect(config['computed'], equals('from-container'));
      expect(config['required'], equals(1));
    });

    test('resolve surfaces configuration exceptions from validator', () {
      const driver = 'manager-error-driver';
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(
        driver,
        () => _RecordingStoreFactory(),
        validator: (config, driverName) {
          throw const ConfigurationException('invalid config');
        },
      );

      final manager = CacheManager(container: Container());
      manager.registerStore('broken', const {'driver': driver});

      expect(
        () => manager.store('broken'),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            equals('invalid config'),
          ),
        ),
      );
    });

    test('legacy drivers resolve without container', () {
      const driver = 'manager-legacy-driver';
      _RecordingStoreFactory? createdFactory;
      addTearDown(() {
        CacheManager.unregisterDriver(driver);
      });
      CacheManager.registerDriver(driver, () {
        final factory = _RecordingStoreFactory();
        createdFactory = factory;
        return factory;
      });

      final manager = CacheManager();
      manager.registerStore('legacy', const {'driver': driver});

      final repository = manager.store('legacy');

      expect(repository, isNotNull);
      expect(createdFactory, isNotNull);
      expect(createdFactory!.lastConfig, isNotNull);
    });

    test('file driver resolves path using StorageDefaults in manager', () {
      final baseDir = Directory.systemTemp.createTempSync(
        'routed-cache-manager-sd-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);
      final container = Container()..instance<StorageDefaults>(storageDefaults);
      final manager = CacheManager(container: container);
      manager.registerStore('file-store', const {'driver': 'file'});

      final repository = manager.store('file-store');
      final store = repository.getStore();

      expect(store, isA<FileStore>());
      expect(
        (store as FileStore).directory.path,
        equals(storageDefaults.frameworkPath('cache')),
      );
    });

    test('file driver resolves path using Config fallback in manager', () {
      final baseDir = Directory.systemTemp.createTempSync(
        'routed-cache-manager-config-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final appConfig = ConfigImpl({
        'storage': {
          'disks': {
            'local': {'root': localRoot},
          },
        },
      });
      final container = Container()..instance<Config>(appConfig);
      final manager = CacheManager(container: container);
      manager.registerStore('file-store', const {'driver': 'file'});

      final repository = manager.store('file-store');
      final store = repository.getStore();

      expect(store, isA<FileStore>());
      expect(
        (store as FileStore).directory.path,
        equals(resolveFrameworkStoragePath(appConfig, child: 'cache')),
      );
    });
  });
}

class _RecordingStoreFactory implements StoreFactory {
  Map<String, dynamic>? lastConfig;

  @override
  Store create(Map<String, dynamic> config) {
    lastConfig = Map<String, dynamic>.from(config);
    return _NoopStore();
  }
}

class _NoopStore implements Store {
  @override
  FutureOr<bool> add(String key, value, [Duration? ttl]) async => true;

  @override
  FutureOr<bool> decrement(String key, [int value = 1]) async => true;

  @override
  FutureOr<bool> forever(String key, value) async => true;

  @override
  FutureOr<bool> forget(String key) async => true;

  @override
  FutureOr<bool> flush() async => true;

  @override
  FutureOr<dynamic> get(String key) async => null;

  @override
  FutureOr<List<String>> getAllKeys() async => const <String>[];

  @override
  String getPrefix() => '';

  @override
  FutureOr<dynamic> increment(String key, [int value = 1]) async => value;

  @override
  FutureOr<Map<String, dynamic>> many(List<String> keys) async =>
      <String, dynamic>{};

  @override
  FutureOr<bool> put(String key, value, int seconds) async => true;

  @override
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds) async =>
      true;
}
