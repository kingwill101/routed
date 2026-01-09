import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('StaticAssetsServiceProvider', () {
    late MemoryFileSystem fs;
    late Directory tempDir;

    setUp(() {
      fs = MemoryFileSystem();
      tempDir = fs.systemTempDirectory.createTempSync('routed_static_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolves mounts using storage disk', () async {
      fs
          .file(fs.path.join(tempDir.path, 'greeting.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('hello');

      final engine = Engine(
        config: EngineConfig(fileSystem: fs),
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': tempDir.path,
                'file_system': fs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              {'route': '/assets', 'disk': 'assets', 'path': ''},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(engine.appConfig.getOrThrow<bool>('static.enabled'), isTrue);
      final mounts = engine.appConfig.getOrThrow<List<dynamic>>(
        'static.mounts',
      );
      expect(mounts.first['disk'], equals('assets'));

      final storage = await engine.make<StorageManager>();
      final resolvedPath = storage.resolve('greeting.txt', disk: 'assets');
      expect(fs.file(resolvedPath).readAsStringSync(), equals('hello'));
    });

    test('storage resolution unaffected when path missing', () async {
      final engine = Engine(
        config: EngineConfig(fileSystem: fs),
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': tempDir.path,
                'file_system': fs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              {'route': '/assets', 'disk': 'assets', 'path': ''},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();
      await Future<void>.delayed(Duration.zero);

      final storage = await engine.make<StorageManager>();
      expect(
        storage.resolve('does_not_exist.txt', disk: 'assets'),
        equals(fs.path.normalize('${tempDir.path}/does_not_exist.txt')),
      );
    });

    test('updates disks after config reload', () async {
      fs
          .file(fs.path.join(tempDir.path, 'old.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');

      final engine = Engine(
        config: EngineConfig(fileSystem: fs),
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': tempDir.path,
                'file_system': fs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              {'route': '/assets', 'disk': 'assets', 'path': ''},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();
      await Future<void>.delayed(Duration.zero);

      final storage = await engine.make<StorageManager>();
      final initialPath = storage.resolve('old.txt', disk: 'assets');
      expect(fs.file(initialPath).readAsStringSync(), equals('old'));

      final newDir = fs.systemTempDirectory.createTempSync('routed_static_new');
      addTearDown(() {
        if (newDir.existsSync()) {
          newDir.deleteSync(recursive: true);
        }
      });
      fs
          .file(fs.path.join(newDir.path, 'fresh.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('fresh');

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('storage', {
        'default': 'assets',
        'disks': {
          'assets': {
            'driver': 'local',
            'root': newDir.path,
            'file_system': fs,
          },
        },
      });
      override.set('static', {
        'enabled': true,
        'mounts': [
          {'route': '/assets', 'disk': 'assets', 'path': ''},
        ],
      });

      await engine.replaceConfig(override);
      await Future<void>.delayed(Duration.zero);

      final updatedPath = storage.resolve('fresh.txt', disk: 'assets');
      expect(fs.file(updatedPath).readAsStringSync(), equals('fresh'));
    });

    test('supports explicit file system mounts', () async {
      final explicitFs = MemoryFileSystem();
      explicitFs.directory('assets').createSync(recursive: true);
      explicitFs
          .file('assets/index.html')
          .writeAsStringSync('<h1>Hello</h1>');

      final engine = Engine(
        config: EngineConfig(fileSystem: explicitFs),
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': 'assets',
                'file_system': explicitFs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              {'route': '/assets', 'disk': 'assets', 'path': ''},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final storage = await engine.make<StorageManager>();
      final resolved = storage.resolve('index.html', disk: 'assets');
      expect(
        explicitFs.file(resolved).readAsStringSync(),
        equals('<h1>Hello</h1>'),
      );

      final global = engine.appConfig.get('http.middleware.global') as List;
      expect(global, contains('routed.static.assets'));
    });
  });
}
