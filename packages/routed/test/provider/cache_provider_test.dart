import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/providers.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:test/test.dart';

void main() {
  group('CacheServiceProvider', () {
    test('configures cache manager from cache config', () async {
      final engine = Engine(
        configItems: {
          'cache': {
            'default': 'memory',
            'stores': {
              'memory': {'driver': 'array'},
              'secondary': {'driver': 'array'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final manager = await engine.make<CacheManager>();
      expect(manager.getDefaultDriver(), equals('memory'));

      // Resolving a configured store should not throw.
      expect(() => manager.store('memory'), returnsNormally);
      expect(() => manager.store('secondary'), returnsNormally);
    });

    test('rebuilds managed cache manager on config reload', () async {
      final engine = Engine(
        configItems: {
          'cache': {
            'default': 'memory',
            'stores': {
              'memory': {'driver': 'array'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final manager1 = await engine.make<CacheManager>();
      final initialDefault = manager1.getDefaultDriver();
      expect(initialDefault, equals('memory'));

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('cache', {
        'default': 'fast',
        'stores': {
          'fast': {'driver': 'array'},
        },
      });

      await engine.replaceConfig(override);
      await Future<void>.delayed(Duration.zero);

      final manager2 = await engine.make<CacheManager>();
      expect(manager2.getDefaultDriver(), equals('fast'));
      expect(() => manager2.store('fast'), returnsNormally);
    });

    test('respects pre-bound cache manager', () async {
      final customManager = CacheManager();
      final engine = Engine(options: [withCacheManager(customManager)]);
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final resolved = await engine.make<CacheManager>();
      expect(identical(resolved, customManager), isTrue);

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('cache', {
        'default': 'memory',
        'stores': {
          'memory': {'driver': 'array'},
        },
      });

      await engine.replaceConfig(override);
      await Future<void>.delayed(Duration.zero);

      final afterReload = await engine.make<CacheManager>();
      expect(identical(afterReload, customManager), isTrue);
    });

    test('registerDriver prevents duplicate cache drivers', () {
      CacheManager.registerDriver(
        'cache-dup',
        () => ArrayStoreFactory(),
        overrideExisting: true,
      );
      addTearDown(() {
        CacheManager.unregisterDriver('cache-dup');
      });

      expect(
        () =>
            CacheManager.registerDriver('cache-dup', () => ArrayStoreFactory()),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cache-dup'),
          ),
        ),
      );
    });

    test('documents driver specific cache options', () {
      CacheManager.registerDriver(
        'custom-doc',
        () => ArrayStoreFactory(),
        documentation: (context) => <ConfigDocEntry>[
          ConfigDocEntry(
            path: context.path('token'),
            type: 'string',
            description: 'API token required for the custom-doc cache driver.',
          ),
        ],
        overrideExisting: true,
      );
      addTearDown(() {
        CacheManager.unregisterDriver('custom-doc');
      });

      final provider = CacheServiceProvider();
      final docPaths = provider.defaultConfig.docs.map((entry) => entry.path);
      expect(docPaths, contains('cache.stores.*.token'));
    });

    test('file cache store uses StorageDefaults path', () async {
      final baseDir = Directory.systemTemp.createTempSync(
        'routed-provider-storage-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final localRoot = p.join(baseDir.path, 'storage', 'app');
      Directory(localRoot).createSync(recursive: true);
      final storageDefaults = StorageDefaults.fromLocalRoot(localRoot);

      final container = Container();
      final config = ConfigImpl({
        'cache': {
          'default': 'file',
          'stores': {
            'file': {'driver': 'file'},
          },
        },
      });
      container.instance<Config>(config);
      container.instance<StorageDefaults>(storageDefaults);

      final provider = CacheServiceProvider();
      provider.register(container);
      await provider.boot(container);

      final manager = container.get<CacheManager>();
      final repository = manager.store('file');
      final store = repository.getStore();

      expect(store, isA<FileStore>());
      expect(
        (store as FileStore).directory.path,
        equals(storageDefaults.frameworkPath('cache')),
      );
    });

    test(
      'file cache store uses Config fallback when StorageDefaults missing',
      () async {
        final baseDir = Directory.systemTemp.createTempSync(
          'routed-provider-config-',
        );
        addTearDown(() {
          if (baseDir.existsSync()) {
            baseDir.deleteSync(recursive: true);
          }
        });
        final localRoot = p.join(baseDir.path, 'storage', 'app');
        Directory(localRoot).createSync(recursive: true);

        final container = Container();
        final config =
            ConfigImpl({
              'cache': {
                'default': 'file',
                'stores': {
                  'file': {'driver': 'file'},
                },
              },
            })..set('storage', {
              'disks': {
                'local': {'root': localRoot},
              },
            });
        container.instance<Config>(config);

        final provider = CacheServiceProvider();
        provider.register(container);
        await provider.boot(container);

        final manager = container.get<CacheManager>();
        final repository = manager.store('file');
        final store = repository.getStore();

        expect(store, isA<FileStore>());
        expect(
          (store as FileStore).directory.path,
          equals(resolveFrameworkStoragePath(config, child: 'cache')),
        );
      },
    );
  });
}
