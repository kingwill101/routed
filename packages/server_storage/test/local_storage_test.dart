import 'package:file/memory.dart';
import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

void main() {
  group('resolveLocalStorageRoot', () {
    test('returns explicit root when provided', () {
      expect(
        resolveLocalStorageRoot('/explicit/root', 'local'),
        '/explicit/root',
      );
    });

    test('returns storageRoot for local disk when no explicit root', () {
      expect(
        resolveLocalStorageRoot(null, 'local', storageRoot: '/custom/storage'),
        '/custom/storage',
      );
    });

    test('ignores storageRoot for non-local disk', () {
      expect(
        resolveLocalStorageRoot(
          null,
          'uploads',
          storageRoot: '/custom/storage',
        ),
        'storage/uploads',
      );
    });

    test('falls back to storage/app for local disk with no storageRoot', () {
      expect(resolveLocalStorageRoot(null, 'local'), 'storage/app');
    });

    test('falls back to storage/<disk> for other disks', () {
      expect(resolveLocalStorageRoot(null, 'backups'), 'storage/backups');
    });

    test('treats empty string root as not provided', () {
      expect(resolveLocalStorageRoot('', 'local'), 'storage/app');
    });

    test('treats whitespace-only root as not provided', () {
      expect(resolveLocalStorageRoot('   ', 'local'), 'storage/app');
    });
  });

  group('LocalStorageDisk', () {
    test('resolve with empty path returns root', () {
      final fs = MemoryFileSystem();
      final disk = LocalStorageDisk(root: '/data', fileSystem: fs);
      expect(disk.resolve(''), '/data');
    });

    test('resolve with subpath joins with root', () {
      final fs = MemoryFileSystem();
      final disk = LocalStorageDisk(root: '/data', fileSystem: fs);
      expect(disk.resolve('images/photo.png'), '/data/images/photo.png');
    });

    test('resolve normalizes path separators', () {
      final fs = MemoryFileSystem();
      final disk = LocalStorageDisk(root: '/data', fileSystem: fs);
      // Path with redundant segments should be normalized.
      expect(disk.resolve('a/../b'), '/data/b');
    });

    test('root getter returns normalized root', () {
      final fs = MemoryFileSystem();
      final disk = LocalStorageDisk(root: '/data', fileSystem: fs);
      expect(disk.root, '/data');
    });

    test('fileSystem getter returns provided filesystem', () {
      final fs = MemoryFileSystem();
      final disk = LocalStorageDisk(root: '/data', fileSystem: fs);
      expect(disk.fileSystem, same(fs));
    });
  });
}
