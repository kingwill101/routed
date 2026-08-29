import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'test_engine.dart';

void main() {
  test('re-exports remote server storage disks', () {
    final disk = S3StorageDisk(
      endpoint: 'objects.example.test',
      accessKey: 'test-access-key',
      secretKey: 'test-secret-key',
      bucket: 'assets',
      region: 'us-east-1',
      pathStyle: true,
    );

    expect(disk, isA<CloudStorageDisk>());
    expect(disk.endpoint, Uri.parse('https://objects.example.test'));

    final sftp = SftpStorageDisk(
      config: const SftpConfig(
        host: 'sftp.example.test',
        username: 'deploy',
        password: 'secret',
      ),
    );
    expect(sftp, isA<FilesystemStorageDisk>());
    expect(sftp.config.host, 'sftp.example.test');
  });

  test('provider exposes an injected S3 disk to request handlers', () async {
    final s3 = S3StorageDisk(
      endpoint: 'objects.example.test',
      accessKey: 'test-access-key',
      secretKey: 'test-secret-key',
      bucket: 'assets',
      region: 'us-east-1',
      pathStyle: true,
    );
    final manager = StorageManager()
      ..registerDisk('assets', s3)
      ..setDefault('assets');
    final engine =
        testEngine(
          providers: [RoutedStorageProvider(manager: manager)],
        )..get('/storage', (ctx) async {
          final storage = ctx.storage();
          final disk = ctx.storageDisk();
          final temporaryUrl = await ctx.temporaryStorageUrl(
            'images/logo.png',
            DateTime.now().add(const Duration(minutes: 5)),
          );
          final temporaryUpload = await ctx.temporaryStorageUploadUrl(
            'images/upload.png',
            DateTime.now().add(const Duration(minutes: 5)),
          );
          final downloadIsSigned = Uri.parse(
            temporaryUrl,
          ).queryParameters.containsKey('X-Amz-Signature');
          final uploadIsSigned = Uri.parse(
            temporaryUpload['url']! as String,
          ).queryParameters.containsKey('X-Amz-Signature');
          return ctx.string(
            '${identical(storage, s3.adapter)}:'
            '${disk.resolve('images/logo.png')}:'
            '$downloadIsSigned:$uploadIsSigned',
          );
        });
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    (await client.get(
      '/storage',
    )).assertStatus(200).assertBodyEquals('true:images/logo.png:true:true');
  });

  test('provider exposes a storage-only filesystem to handlers', () async {
    final fs = MemoryFileSystem();
    final filesystem = LocalStorageDisk(root: '/r2', fileSystem: fs).storage;
    final manager = StorageManager()
      ..registerFilesystem('r2', filesystem)
      ..setDefault('r2');
    final engine =
        testEngine(
          providers: [RoutedStorageProvider(manager: manager)],
        )..get('/storage-only', (ctx) async {
          final storage = ctx.storage();
          await storage.put('object.txt', 'native-binding');
          return ctx.string((await storage.get('object.txt'))!);
        });
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    (await client.get(
      '/storage-only',
    )).assertStatus(200).assertBodyEquals('native-binding');
  });

  test(
    'StorageConfig applies typed local disks without a supplied manager',
    () async {
      final fs = MemoryFileSystem();
      fs.directory('/assets').createSync();

      final engine = testEngine(
        fileSystem: fs,
        providers: [
          RoutedStorageProvider(
            configuration: StorageConfig(
              defaultDisk: 'assets',
              disks: {'assets': const LocalStorageDiskConfig(root: '/assets')},
            ),
          ),
        ],
      );
      await engine.initialize();
      addTearDown(engine.close);

      final manager = await engine.container.make<StorageManager>();
      expect(manager.defaultDisk, 'assets');
      expect(manager.disk('assets'), isA<LocalStorageDisk>());
      expect((manager.disk('assets') as LocalStorageDisk).root, '/assets');
    },
  );

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
      providers: [
        RoutedStorageProvider(manager: manager),
        RoutedStaticProvider(
          StaticConfig(
            enabled: true,
            mounts: [const StaticMountConfig(route: '/assets', disk: 'assets')],
          ),
        ),
      ],
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

  test('static.mounts preserves path-only custom disks', () async {
    final fs = MemoryFileSystem();
    fs.directory('/legacy').createSync();
    fs.file('/legacy/readme.txt').writeAsStringSync('legacy');
    final manager = StorageManager()
      ..registerDisk('legacy', _PathOnlyStaticDisk(fs, '/legacy'))
      ..setDefault('legacy');
    final engine = testEngine(
      providers: [
        RoutedStorageProvider(manager: manager),
        RoutedStaticProvider(
          StaticConfig(
            enabled: true,
            mounts: [
              const StaticMountConfig(route: '/legacy', disk: 'legacy'),
            ],
          ),
        ),
      ],
    );
    await engine.initialize();
    addTearDown(engine.close);
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    (await client.get(
      '/legacy/readme.txt',
    )).assertStatus(200).assertBodyEquals('legacy');
  });

  test('static.mounts serves a storage-only filesystem', () async {
    final fs = MemoryFileSystem();
    final filesystem = LocalStorageDisk(root: '/r2', fileSystem: fs).storage;
    await filesystem.put('public/index.html', 'r2 home');
    await filesystem.put('public/app.css', 'body {}');
    await filesystem.put('public/docs/index.html', 'nested index');
    final manager = StorageManager()
      ..registerFilesystem('r2', filesystem)
      ..setDefault('r2');

    final engine = testEngine(
      fileSystem: fs,
      providers: [
        RoutedStorageProvider(manager: manager),
        RoutedStaticProvider(
          StaticConfig(
            enabled: true,
            mounts: [
              const StaticMountConfig(
                route: '/r2-assets',
                disk: 'r2',
                path: 'public',
              ),
            ],
          ),
        ),
      ],
    );
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    (await client.get(
      '/r2-assets',
    )).assertStatus(200).assertBodyEquals('r2 home');
    (await client.get(
      '/r2-assets/app.css',
    )).assertStatus(200).assertBodyEquals('body {}');
    (await client.get(
      '/r2-assets/docs',
    )).assertStatus(200).assertBodyEquals('nested index');
    (await client.get(
          '/r2-assets/app.css',
          headers: const {
            'range': ['bytes=1-4'],
          },
        ))
        .assertStatus(206)
        .assertBodyEquals('ody ')
        .assertHeader('content-range', 'bytes 1-4/7');
    final head = await client.head('/r2-assets/app.css');
    head.assertStatus(200);
    expect(head.body, isEmpty);
    (await client.get('/r2-assets/missing.css')).assertStatus(404);
  });

  test('storage static mounts cannot escape their configured prefix', () async {
    final fs = MemoryFileSystem();
    final filesystem = LocalStorageDisk(root: '/r2', fileSystem: fs).storage;
    await filesystem.put('public/visible.txt', 'visible');
    await filesystem.put('private/secret.txt', 'private-canary');
    final manager = StorageManager()
      ..registerFilesystem('r2', filesystem)
      ..setDefault('r2');

    final engine = testEngine(
      fileSystem: fs,
      providers: [
        RoutedStorageProvider(manager: manager),
        RoutedStaticProvider(
          StaticConfig(
            enabled: true,
            mounts: [
              const StaticMountConfig(
                route: '/r2-assets',
                disk: 'r2',
                path: 'public',
              ),
            ],
          ),
        ),
      ],
    );
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    (await client.get(
      '/r2-assets/visible.txt',
    )).assertStatus(200).assertBodyEquals('visible');
    for (final requestPath in const <String>[
      '/r2-assets/private/secret.txt',
      '/r2-assets/%2e%2e/private/secret.txt',
      '/r2-assets/%252e%252e/private/secret.txt',
      '/r2-assets/..%2Fprivate/secret.txt',
      '/r2-assets/%2e%2e%2fprivate/secret.txt',
    ]) {
      final response = await client.get(requestPath);
      expect(response.statusCode, anyOf(403, 404), reason: requestPath);
      expect(response.body, isNot(contains('private-canary')));
    }
  });

  test(
    'filesystem-backed remote disks use asynchronous static listing',
    () async {
      final storageFs = MemoryFileSystem();
      final storage = LocalStorageDisk(
        root: '/remote',
        fileSystem: storageFs,
      ).storage;
      await storage.put('public/docs/readme.txt', 'remote');
      final disk = _AsyncOnlyStaticDisk(
        fileSystem: MemoryFileSystem(),
        storage: storage,
      );
      final manager = StorageManager()
        ..registerDisk('remote', disk)
        ..setDefault('remote');

      final engine = testEngine(
        providers: [
          RoutedStorageProvider(manager: manager),
          RoutedStaticProvider(
            StaticConfig(
              enabled: true,
              mounts: [
                const StaticMountConfig(
                  route: '/remote',
                  disk: 'remote',
                  path: 'public',
                  listDirectories: true,
                ),
              ],
            ),
          ),
        ],
      );
      await engine.initialize();
      addTearDown(engine.close);
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final withoutSlash = await client.get('/remote/docs');
      withoutSlash
          .assertStatus(200)
          .assertBodyContains('href="/remote/docs/readme.txt"');
      final withSlash = await client.get('/remote/docs/');
      withSlash
          .assertStatus(200)
          .assertBodyContains('href="/remote/docs/readme.txt"');
    },
  );

  test('static mounts are fixed for the engine lifetime', () async {
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
      providers: [
        RoutedStorageProvider(manager: manager),
        RoutedStaticProvider(
          StaticConfig(
            enabled: true,
            mounts: [const StaticMountConfig(route: '/files', disk: 'one')],
          ),
        ),
      ],
    );
    await engine.initialize();
    addTearDown(engine.close);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    (await client.get(
      '/files/one.txt',
    )).assertStatus(200).assertBodyEquals('one');

    (await client.get(
      '/files/one.txt',
    )).assertStatus(200).assertBodyEquals('one');
  });
}

final class _AsyncOnlyStaticDisk implements AsyncFilesystemStorageDisk {
  const _AsyncOnlyStaticDisk({
    required this.fileSystem,
    required this.storage,
  });

  @override
  final FileSystem fileSystem;

  @override
  final Filesystem storage;

  @override
  String resolve(String path) => path;
}

final class _PathOnlyStaticDisk implements StorageDisk {
  const _PathOnlyStaticDisk(this.fileSystem, this.root);

  @override
  final FileSystem fileSystem;

  final String root;

  @override
  String resolve(String path) {
    if (path.isEmpty) return root;
    return fileSystem.path.join(root, path);
  }
}
