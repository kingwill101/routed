import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

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
      fs.file(fs.path.join(tempDir.path, 'greeting.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('hello');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
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
      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
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
      fs.file(fs.path.join(tempDir.path, 'old.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
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
      fs.file(fs.path.join(newDir.path, 'fresh.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('fresh');

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('storage', {
        'default': 'assets',
        'disks': {
          'assets': {'driver': 'local', 'root': newDir.path, 'file_system': fs},
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
      explicitFs.file('assets/index.html').writeAsStringSync('<h1>Hello</h1>');

      final engine = testEngine(
        config: EngineConfig(fileSystem: explicitFs),
        fileSystem: explicitFs,
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

    test('serves mounted directories via static assets provider', () async {
      final mountDir = fs.directory(fs.path.join(tempDir.path, 'public'))
        ..createSync(recursive: true);
      mountDir.childFile('hello.txt').writeAsStringSync('hello from provider');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
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
              {'route': '/assets', 'disk': 'assets', 'path': 'public'},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.get('/assets/hello.txt');
      response
        ..assertStatus(200)
        ..assertBodyEquals('hello from provider');
    });

    test('serves entire directory tree with path: empty string', () async {
      // Create a directory structure like:
      // public/
      //   css/
      //     style.css
      //   js/
      //     app.js
      //   images/
      //     logo.png
      //   index.html
      final publicDir = fs.directory(fs.path.join(tempDir.path, 'public'))
        ..createSync(recursive: true);

      // Create subdirectories and files
      final cssDir = publicDir.childDirectory('css')..createSync();
      cssDir.childFile('style.css').writeAsStringSync('body { color: red; }');

      final jsDir = publicDir.childDirectory('js')..createSync();
      jsDir.childFile('app.js').writeAsStringSync('console.log("hello");');

      final imagesDir = publicDir.childDirectory('images')..createSync();
      imagesDir.childFile('logo.png').writeAsStringSync('PNG_DATA');

      publicDir.childFile('index.html').writeAsStringSync('<html>index</html>');

      // Deep nested directory
      final deepDir = publicDir.childDirectory('a/b/c')
        ..createSync(recursive: true);
      deepDir.childFile('deep.txt').writeAsStringSync('deeply nested');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': publicDir.path,
                'file_system': fs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              // Single mount with path: '' should serve ALL subdirectories
              {'route': '/assets', 'disk': 'assets', 'path': ''},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      // Test root level file
      (await client.get('/assets/index.html'))
        ..assertStatus(200)
        ..assertBodyEquals('<html>index</html>');

      // Test css subdirectory
      (await client.get('/assets/css/style.css'))
        ..assertStatus(200)
        ..assertBodyEquals('body { color: red; }');

      // Test js subdirectory
      (await client.get('/assets/js/app.js'))
        ..assertStatus(200)
        ..assertBodyEquals('console.log("hello");');

      // Test images subdirectory
      (await client.get('/assets/images/logo.png'))
        ..assertStatus(200)
        ..assertBodyEquals('PNG_DATA');

      // Test deeply nested path
      (await client.get('/assets/a/b/c/deep.txt'))
        ..assertStatus(200)
        ..assertBodyEquals('deeply nested');

      // Test non-existent file returns 404
      (await client.get('/assets/nonexistent.txt')).assertStatus(404);

      // Test non-existent subdirectory returns 404
      (await client.get('/assets/fake/file.txt')).assertStatus(404);
    });

    test('serves entire directory when path is omitted', () async {
      final publicDir = fs.directory(fs.path.join(tempDir.path, 'public'))
        ..createSync(recursive: true);

      publicDir.childDirectory('css').createSync();
      publicDir
          .childDirectory('css')
          .childFile('style.css')
          .writeAsStringSync('body {}');

      publicDir.childDirectory('js').createSync();
      publicDir
          .childDirectory('js')
          .childFile('app.js')
          .writeAsStringSync('alert(1)');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        configItems: {
          'storage': {
            'default': 'assets',
            'disks': {
              'assets': {
                'driver': 'local',
                'root': publicDir.path,
                'file_system': fs,
              },
            },
          },
          'static': {
            'enabled': true,
            'mounts': [
              // No 'path' key at all - should default to '' and serve entire disk
              {'route': '/assets', 'disk': 'assets'},
            ],
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      (await client.get('/assets/css/style.css'))
        ..assertStatus(200)
        ..assertBodyEquals('body {}');

      (await client.get('/assets/js/app.js'))
        ..assertStatus(200)
        ..assertBodyEquals('alert(1)');
    });
  });
}
