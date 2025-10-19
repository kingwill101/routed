import 'dart:io';

import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('StaticAssetsServiceProvider', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('routed_static_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolves mounts using storage disk', () async {
      File('${tempDir.path}/greeting.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('hello');

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {'driver': 'local', 'root': tempDir.path},
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

      expect(engine.appConfig.get('static.enabled'), isTrue);
      final mounts = engine.appConfig.get('static.mounts') as List;
      expect(mounts.first['disk'], equals('assets'));

      final storage = await engine.make<StorageManager>();
      final resolvedPath = storage.resolve('greeting.txt', disk: 'assets');
      expect(File(resolvedPath).readAsStringSync(), equals('hello'));
    });

    test('storage resolution unaffected when path missing', () async {
      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {'driver': 'local', 'root': tempDir.path},
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
        equals(p.normalize('${tempDir.path}/does_not_exist.txt')),
      );
    });

    test('updates disks after config reload', () async {
      File('${tempDir.path}/old.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {'driver': 'local', 'root': tempDir.path},
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
      expect(File(initialPath).readAsStringSync(), equals('old'));

      final newDir = Directory.systemTemp.createTempSync('routed_static_new');
      addTearDown(() {
        if (newDir.existsSync()) {
          newDir.deleteSync(recursive: true);
        }
      });
      File('${newDir.path}/fresh.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('fresh');

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('storage', {
        'default': 'assets',
        'disks': {
          'assets': {'driver': 'local', 'root': newDir.path},
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
      expect(File(updatedPath).readAsStringSync(), equals('fresh'));
    });

    test('supports explicit file system mounts', () async {
      final fs = MemoryFileSystem();
      fs.directory('assets').createSync(recursive: true);
      fs.file('assets/index.html').writeAsStringSync('<h1>Hello</h1>');

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': 'assets',
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

      final storage = await engine.make<StorageManager>();
      final resolved = storage.resolve('index.html', disk: 'assets');
      expect(fs.file(resolved).readAsStringSync(), equals('<h1>Hello</h1>'));

      final global = engine.appConfig.get('http.middleware.global') as List;
      expect(global, contains('routed.static.assets'));
    });
  });
}
