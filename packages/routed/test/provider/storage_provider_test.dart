import 'package:file/file.dart' as storage_file;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/providers.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
import 'package:test/test.dart';

void main() {
  group('StorageServiceProvider', () {
    test('registers disks from config', () async {
      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'local': {'driver': 'local', 'root': 'storage/app'},
              'assets': {'driver': 'local', 'root': 'public/assets'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      expect(storage.defaultDisk, equals('assets'));

      final resolved = storage.resolve('logo.png');
      expect(resolved, endsWith(p.normalize('public/assets/logo.png')));
      expect(
        storage.resolve('cache/data.json', disk: 'local'),
        endsWith(p.normalize('storage/app/cache/data.json')),
      );
    });

    test('honors storage.root when local disk root not specified', () async {
      final engine = Engine(
        configItems: {
          'storage': {
            'root': '/var/data',
            'disks': {
              'local': {'driver': 'local'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      expect(storage.defaultDisk, equals('local'));
      expect(
        storage.resolve('hello.txt'),
        endsWith(p.normalize('var/data/hello.txt')),
      );
    });

    test('provides fallback disk when config missing', () async {
      final engine = Engine();
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      expect(storage.defaultDisk, equals('local'));
      expect(
        storage.resolve('foo.txt'),
        endsWith(p.normalize('storage/app/foo.txt')),
      );
    });

    test('allows registering custom storage driver', () async {
      StorageServiceProvider.registerDriver('memory', (context) {
        final root =
            context.configuration['root']?.toString() ??
            'custom/${context.diskName}';
        return LocalStorageDisk(
          root: root,
          fileSystem: context.manager.defaultFileSystem,
        );
      }, overrideExisting: true);
      addTearDown(() {
        StorageServiceProvider.unregisterDriver('memory');
      });

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'memory',
            'disks': {
              'memory': {'driver': 'memory', 'root': 'custom/storage'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      expect(
        storage.resolve('item.txt'),
        endsWith(p.normalize('custom/storage/item.txt')),
      );
    });

    test('registerDriver prevents duplicate storage drivers', () {
      StorageServiceProvider.registerDriver(
        'storage-dup',
        (context) => LocalStorageDisk(
          root: 'dup/${context.diskName}',
          fileSystem: context.manager.defaultFileSystem,
        ),
        overrideExisting: true,
      );
      addTearDown(() {
        StorageServiceProvider.unregisterDriver('storage-dup');
      });

      expect(
        () => StorageServiceProvider.registerDriver(
          'storage-dup',
          (context) => LocalStorageDisk(
            root: 'dup/${context.diskName}',
            fileSystem: context.manager.defaultFileSystem,
          ),
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('storage-dup'),
          ),
        ),
      );
    });

    test('custom driver override takes precedence over built-in', () async {
      StorageServiceProvider.unregisterDriver('local');
      StorageServiceProvider.registerDriver(
        'local',
        (context) => LocalStorageDisk(
          root: 'override/${context.diskName}',
          fileSystem: context.manager.defaultFileSystem,
        ),
        overrideExisting: true,
      );
      addTearDown(() {
        StorageServiceProvider.unregisterDriver('local');
        StorageServiceProvider.registerDriver(
          'local',
          (context) {
            final root =
                parseStringLike(
                  context.configuration['root'],
                  context: 'storage.disks.${context.diskName}.root',
                  allowEmpty: true,
                  coerceNonString: true,
                  throwOnInvalid: false,
                ) ??
                'storage/${context.diskName}';
            final override = context.configuration['file_system'];
            final fs = override is storage_file.FileSystem
                ? override
                : context.manager.defaultFileSystem;
            return LocalStorageDisk(root: root, fileSystem: fs);
          },
          documentation: (ctx) {
            return <ConfigDocEntry>[
              ConfigDocEntry(
                path: ctx.path('file_system'),
                type: 'FileSystem',
                description:
                    'Optional file system override used when operating the local disk.',
              ),
            ];
          },
          overrideExisting: true,
        );
      });

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'local',
            'disks': {
              'local': {'driver': 'local'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      expect(
        storage.resolve('foo.txt'),
        endsWith(p.normalize('override/local/foo.txt')),
      );
    });

    test('documents driver specific storage options', () {
      StorageServiceProvider.registerDriver(
        'memory-docs',
        (context) => LocalStorageDisk(
          root: 'docs/${context.diskName}',
          fileSystem: context.manager.defaultFileSystem,
        ),
        documentation: (context) => <ConfigDocEntry>[
          ConfigDocEntry(
            path: context.path('token'),
            type: 'string',
            description: 'Authentication token used by the memory-docs driver.',
          ),
        ],
        overrideExisting: true,
      );
      addTearDown(() {
        StorageServiceProvider.unregisterDriver('memory-docs');
      });

      final provider = StorageServiceProvider();
      final docPaths = provider.defaultConfig.docs.map((entry) => entry.path);
      expect(docPaths, contains('storage.disks.memory-docs.token'));
    });

    test('initializes storage facade alongside storage manager', () async {
      final fs = MemoryFileSystem();
      final tempDir = fs.systemTempDirectory.createTempSync('routed_storage');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final engine = Engine(
        config: EngineConfig(fileSystem: fs),
        configItems: {
          'storage': {
            'default': 'local',
            'disks': {
              'local': {
                'driver': 'local',
                'root': tempDir.path,
                'file_system': fs,
              },
              'secondary': {
                'driver': 'local',
                'root': fs.path.join(tempDir.path, 'secondary'),
                'file_system': fs,
              },
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      await Storage.put('hello.txt', 'facade');
      expect(
        fs
            .file(fs.path.join(tempDir.path, 'hello.txt'))
            .readAsStringSync(),
        equals('facade'),
      );

      final secondary = Storage.disk('secondary');
      await secondary.put('nested/world.txt', 'routing');
      expect(
        fs
            .file(
              fs.path.join(
                tempDir.path,
                'secondary',
                'nested',
                'world.txt',
              ),
            )
            .readAsStringSync(),
        equals('routing'),
      );
    });

    test('exposes built-in cloud storage driver', () {
      expect(StorageServiceProvider.availableDriverNames(), contains('s3'));
    });
  });
}
