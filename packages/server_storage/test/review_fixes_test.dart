import 'package:file/file.dart' as file;
import 'package:file/memory.dart';
import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

class _FakeDisk implements StorageDisk {
  _FakeDisk();

  @override
  file.FileSystem get fileSystem => MemoryFileSystem();

  @override
  String resolve(String path) => path;
}

void main() {
  group('LocalStorageDisk.resolve', () {
    test('joins relative paths inside the root', () {
      final disk = LocalStorageDisk(
        root: '/storage/app',
        fileSystem: MemoryFileSystem(),
      );
      final resolved = disk.resolve('uploads/avatar.png');
      expect(resolved, '/storage/app/uploads/avatar.png');
    });

    test('rejects parent segments that escape the root', () {
      final disk = LocalStorageDisk(
        root: '/storage/app',
        fileSystem: MemoryFileSystem(),
      );
      expect(
        () => disk.resolve('../../etc/passwd'),
        throwsArgumentError,
        reason: 'relative escape via .. must be rejected',
      );
      expect(
        () => disk.resolve('uploads/../../etc/passwd'),
        throwsArgumentError,
      );
    });

    test('rejects absolute paths', () {
      final disk = LocalStorageDisk(
        root: '/storage/app',
        fileSystem: MemoryFileSystem(),
      );
      expect(
        () => disk.resolve('/etc/passwd'),
        throwsArgumentError,
        reason: 'absolute input must not bypass the root',
      );
    });

    test('treats the empty path as the root itself', () {
      final disk = LocalStorageDisk(
        root: '/storage/app',
        fileSystem: MemoryFileSystem(),
      );
      expect(disk.resolve(''), disk.root);
    });

    test('does not treat sibling roots as inside the disk', () {
      final disk = LocalStorageDisk(
        root: '/storage/app',
        fileSystem: MemoryFileSystem(),
      );
      // '/storage/app2' must not be considered inside '/storage/app'.
      expect(
        () => disk.resolve('/storage/app2/x'),
        throwsArgumentError,
      );
    });
  });

  group('StorageManager.registerDisk', () {
    test('rejects empty disk names', () {
      final manager = StorageManager();
      expect(
        () => manager.registerDisk('', _FakeDisk()),
        throwsArgumentError,
        reason: 'an empty name would register a disk unreachable via disk()',
      );
      expect(manager.hasDisk(''), isFalse);
    });

    test('registers and resolves non-empty names', () {
      final manager = StorageManager();
      final disk = _FakeDisk();
      manager.registerDisk('uploads', disk);
      expect(manager.hasDisk('uploads'), isTrue);
      expect(manager.disk('uploads'), same(disk));
    });

    test('default disk selection still works', () {
      final manager = StorageManager();
      final local = _FakeDisk();
      manager
        ..registerDisk('local', local)
        ..setDefault('local');
      expect(manager.disk(), same(local));
      expect(manager.disk(''), same(local));
    });
  });
}
