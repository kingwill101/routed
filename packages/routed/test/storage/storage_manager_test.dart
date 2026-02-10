import 'package:file/memory.dart';
import 'package:routed/src/storage/storage_manager.dart';
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
      manager.registerDisk('custom', _InMemoryDisk(fs));
      manager.setDefault('custom');
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
      manager.registerDisk('local', _InMemoryDisk(fs));
      manager.registerDisk('backup', _InMemoryDisk(fs));
      // Using explicit disk name.
      expect(manager.resolve('data', disk: 'backup'), '/data');
    });

    test('clear removes all disks', () {
      manager.registerDisk('a', _InMemoryDisk(fs));
      manager.registerDisk('b', _InMemoryDisk(fs));
      expect(manager.hasDisk('a'), isTrue);
      manager.clear();
      expect(manager.hasDisk('a'), isFalse);
      expect(manager.hasDisk('b'), isFalse);
    });

    test('defaultFileSystem returns provided filesystem', () {
      expect(manager.defaultFileSystem, same(fs));
    });
  });
}
