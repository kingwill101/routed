import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'test_engine.dart';

void main() {
  test('static.mounts serves files from a configured storage disk', () async {
    final fs = MemoryFileSystem();
    final publicDirectory = fs.directory('/public')..createSync();
    publicDirectory.childFile('index.html').writeAsStringSync('home');
    publicDirectory.childFile('app.css').writeAsStringSync('body {}');
    final manager = StorageManager(defaultFileSystem: fs)
      ..registerDisk(
        'assets',
        LocalStorageDisk(root: '/public', fileSystem: fs),
      )
      ..setDefault('assets');

    final engine = testEngine(
      fileSystem: fs,
      configItems: {
        'static': {
          'enabled': true,
          'mounts': [
            {'route': '/assets', 'disk': 'assets'},
          ],
        },
      },
      providers: [RoutedStorageProvider(manager), RoutedStaticProvider()],
    );
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final css = await client.get('/assets/app.css');
    css.assertStatus(200).assertBodyEquals('body {}');
    (await client.get('/assets')).assertStatus(200).assertBodyEquals('home');
    final head = await client.head('/assets/app.css');
    head.assertStatus(200);
    final missing = await client.get('/assets/missing.css');
    missing.assertStatus(404);
  });

  test('static.mounts can be disabled and reconfigured on reload', () async {
    final fs = MemoryFileSystem();
    fs.directory('/one').createSync();
    fs.directory('/two').createSync();
    fs.directory('/one').childFile('one.txt').writeAsStringSync('one');
    fs.directory('/two').childFile('two.txt').writeAsStringSync('two');

    final manager = StorageManager(defaultFileSystem: fs)
      ..registerDisk('one', LocalStorageDisk(root: '/one', fileSystem: fs))
      ..registerDisk('two', LocalStorageDisk(root: '/two', fileSystem: fs));

    final engine = testEngine(
      fileSystem: fs,
      configItems: {
        'static': {
          'enabled': true,
          'mounts': [
            {'route': '/files', 'disk': 'one'},
          ],
        },
      },
      providers: [RoutedStorageProvider(manager), RoutedStaticProvider()],
    );
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    (await client.get(
      '/files/one.txt',
    )).assertStatus(200).assertBodyEquals('one');

    await engine.replaceConfig(
      ConfigImpl({
        'static': {
          'enabled': true,
          'mounts': [
            {'route': '/assets', 'disk': 'two'},
          ],
        },
      }),
    );

    (await client.get('/files/one.txt')).assertStatus(404);
    (await client.get(
      '/assets/two.txt',
    )).assertStatus(200).assertBodyEquals('two');
  });
}
