import 'package:file/memory.dart';
import 'package:server_data/server_data.dart';
import 'package:test/test.dart';

void main() {
  group('resolveLocalStorageRoot', () {
    test('prefers explicit root', () {
      expect(resolveLocalStorageRoot('/explicit', 'local'), '/explicit');
    });

    test('uses storageRoot for local disk when explicit root is missing', () {
      expect(
        resolveLocalStorageRoot(null, 'local', storageRoot: '/storage-root'),
        '/storage-root',
      );
    });

    test('falls back to default disk roots', () {
      expect(resolveLocalStorageRoot(null, 'local'), 'storage/app');
      expect(resolveLocalStorageRoot(null, 'uploads'), 'storage/uploads');
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
