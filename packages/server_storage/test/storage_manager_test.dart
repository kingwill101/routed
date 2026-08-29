import 'package:file/memory.dart';
import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

/// Minimal in-memory disk for testing.
class _InMemoryDisk implements StorageDisk {
  _InMemoryDisk(this._fs);

  final MemoryFileSystem _fs;

  @override
  MemoryFileSystem get fileSystem => _fs;

  @override
  String resolve(String path) => path.isEmpty ? '/' : '/$path';
}

final class _TemporaryUrlDisk implements TemporaryUrlStorageDisk {
  _TemporaryUrlDisk(this._fs);

  final MemoryFileSystem _fs;
  String? lastPath;
  DateTime? lastExpiration;
  Map<String, dynamic>? lastOptions;

  @override
  MemoryFileSystem get fileSystem => _fs;

  @override
  String resolve(String path) => path;

  @override
  Future<String> temporaryUrl(
    String path,
    DateTime expiration, {
    Map<String, dynamic>? options,
  }) async {
    lastPath = path;
    lastExpiration = expiration;
    lastOptions = options;
    return 'https://storage.example.test/download/$path';
  }

  @override
  Future<Map<String, dynamic>> temporaryUploadUrl(
    String path,
    DateTime expiration, {
    Map<String, dynamic>? options,
  }) async {
    lastPath = path;
    lastExpiration = expiration;
    lastOptions = options;
    return <String, dynamic>{
      'url': 'https://storage.example.test/upload/$path',
      'headers': const <String, String>{'x-upload-token': 'token'},
    };
  }
}

void main() {
  group('StorageManager', () {
    late StorageManager manager;
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
      manager = StorageManager(defaultFileSystem: fs);
    });

    test('registerDisk and hasDisk lifecycle', () {
      expect(manager.hasDisk('test'), isFalse);
      manager.registerDisk('test', _InMemoryDisk(fs));
      expect(manager.hasDisk('test'), isTrue);
    });

    test('disk returns registered disk', () {
      final disk = _InMemoryDisk(fs);
      manager.registerDisk('uploads', disk);
      expect(manager.disk('uploads'), same(disk));
    });

    test('disk throws for unregistered name', () {
      expect(() => manager.disk('nonexistent'), throwsA(isA<StateError>()));
    });

    test('setDefault changes default disk', () {
      manager
        ..registerDisk('custom', _InMemoryDisk(fs))
        ..setDefault('custom');
      expect(manager.defaultDisk, 'custom');
      // disk() with no argument uses default.
      expect(manager.disk(), isA<StorageDisk>());
    });

    test('setDefault with empty name throws ArgumentError', () {
      expect(() => manager.setDefault(''), throwsA(isA<ArgumentError>()));
    });

    test('resolve delegates to disk.resolve', () {
      final disk = _InMemoryDisk(fs);
      manager.registerDisk('local', disk);
      expect(manager.resolve('foo/bar'), '/foo/bar');
    });

    test('resolve with explicit disk name', () {
      manager
        ..registerDisk('local', _InMemoryDisk(fs))
        ..registerDisk('backup', _InMemoryDisk(fs));
      // Using explicit disk name.
      expect(manager.resolve('data', disk: 'backup'), '/data');
    });

    test('clear removes all disks', () {
      manager
        ..registerDisk('a', _InMemoryDisk(fs))
        ..registerDisk('b', _InMemoryDisk(fs));
      expect(manager.hasDisk('a'), isTrue);
      manager.clear();
      expect(manager.hasDisk('a'), isFalse);
      expect(manager.hasDisk('b'), isFalse);
    });

    test('defaultFileSystem returns provided filesystem', () {
      expect(manager.defaultFileSystem, same(fs));
    });

    test('storage exposes unified operations for a local disk', () async {
      manager
        ..registerDisk('local', LocalStorageDisk(root: '/data', fileSystem: fs))
        ..setDefault('local');

      final storage = manager.storage();
      expect(await storage.put('notes/hello.txt', 'hello'), isTrue);
      expect(await storage.get('notes/hello.txt'), 'hello');
      expect(await storage.exists('notes/hello.txt'), isTrue);
      expect(manager.drive(), same(storage));

      expect(await storage.put('../outside.txt', 'outside'), isTrue);
      expect(fs.file('/outside.txt').existsSync(), isFalse);
      expect(fs.file('/data/outside.txt').readAsStringSync(), 'outside');
    });

    test('storage rejects path-only custom disks', () {
      manager
        ..registerDisk('custom', _InMemoryDisk(fs))
        ..setDefault('custom');

      expect(() => manager.storage(), throwsUnsupportedError);
    });

    test(
      'registerFilesystem supports host-native storage-only disks',
      () async {
        final filesystem = LocalStorageDisk(
          root: '/native',
          fileSystem: fs,
        ).storage;
        manager
          ..registerFilesystem('r2', filesystem)
          ..setDefault('r2');

        expect(manager.hasDisk('r2'), isTrue);
        expect(manager.diskNames, ['r2']);
        expect(manager.supportsPathResolution(), isFalse);
        expect(manager.supportsFilesystemOperations(), isTrue);
        expect(manager.storage(), same(filesystem));
        expect(manager.drive(), same(filesystem));
        expect(await manager.storage().put('object.txt', 'native'), isTrue);
        expect(await manager.storage().get('object.txt'), 'native');
        expect(() => manager.disk(), throwsUnsupportedError);
        expect(() => manager.resolve('object.txt'), throwsUnsupportedError);
      },
    );

    test('registerDisk and registerFilesystem replace the same name', () {
      final filesystem = LocalStorageDisk(
        root: '/native',
        fileSystem: fs,
      ).storage;
      final disk = _InMemoryDisk(fs);

      manager.registerFilesystem('shared', filesystem);
      expect(manager.storage('shared'), same(filesystem));

      manager.registerDisk('shared', disk);
      expect(manager.supportsPathResolution('shared'), isTrue);
      expect(manager.supportsFilesystemOperations('shared'), isFalse);
      expect(manager.disk('shared'), same(disk));
      expect(() => manager.storage('shared'), throwsUnsupportedError);
      expect(manager.diskNames, ['shared']);
    });

    test('supportsPathResolution rejects an unknown disk', () {
      expect(
        () => manager.supportsPathResolution('missing'),
        throwsStateError,
      );
    });

    test('supportsFilesystemOperations rejects an unknown disk', () {
      expect(
        () => manager.supportsFilesystemOperations('missing'),
        throwsStateError,
      );
    });

    test('temporaryUrl delegates through the storage abstraction', () async {
      final disk = _TemporaryUrlDisk(fs);
      final expiration = DateTime.utc(2030);
      const options = <String, dynamic>{'response-content-type': 'text/plain'};
      manager
        ..registerDisk('private', disk)
        ..setDefault('private');

      final url = await manager.temporaryUrl(
        'reports/monthly.txt',
        expiration,
        options: options,
      );

      expect(url, 'https://storage.example.test/download/reports/monthly.txt');
      expect(disk.lastPath, 'reports/monthly.txt');
      expect(disk.lastExpiration, expiration);
      expect(disk.lastOptions, same(options));
    });

    test('temporaryUploadUrl delegates to an explicitly named disk', () async {
      final disk = _TemporaryUrlDisk(fs);
      final expiration = DateTime.utc(2030);
      manager.registerDisk('uploads', disk);

      final result = await manager.temporaryUploadUrl(
        'incoming/report.txt',
        expiration,
        disk: 'uploads',
      );

      expect(
        result,
        {
          'url': 'https://storage.example.test/upload/incoming/report.txt',
          'headers': {'x-upload-token': 'token'},
        },
      );
      expect(disk.lastPath, 'incoming/report.txt');
      expect(disk.lastExpiration, expiration);
    });

    test('temporary URLs reject disks without that capability', () async {
      manager
        ..registerDisk('local', LocalStorageDisk(root: '/data', fileSystem: fs))
        ..setDefault('local');

      await expectLater(
        manager.temporaryUrl('private.txt', DateTime.utc(2030)),
        throwsUnsupportedError,
      );
      await expectLater(
        manager.temporaryUploadUrl(
          'private.txt',
          DateTime.utc(2030),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
