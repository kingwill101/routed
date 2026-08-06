import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:test/test.dart';

void main() {
  group('FileStore Tests', () {
    late Store store;
    late FileStore fileStore;
    late Directory tempDir;
    late FileSystem fileSystem;

    setUp(() {
      fileSystem = MemoryFileSystem();
      tempDir = fileSystem.systemTempDirectory.createTempSync();
      fileStore = FileStore(tempDir, null, null, fileSystem);
      store = fileStore;
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('put and get item', () async {
      await store.put('key', 'value', 60);
      final value = await store.get('key');
      expect(value, 'value');
    });

    test('put and forget item', () async {
      await store.put('key', 'value', 60);
      await store.forget('key');
      final value = await store.get('key');
      expect(value, isNull);
    });

    test('increment and decrement item', () async {
      await store.put('counter', 1, 60);
      await store.increment('counter', 1);
      var value = await store.get('counter');
      expect(value, 2);

      await store.decrement('counter', 1);
      value = await store.get('counter');
      expect(value, 1);
    });

    test('put item forever', () async {
      await store.forever('key', 'value');
      final value = await store.get('key');
      expect(value, 'value');
    });

    test('flush all items', () async {
      await store.put('key1', 'value1', 60);
      await store.put('key2', 'value2', 60);
      await store.flush();
      final value1 = await store.get('key1');
      final value2 = await store.get('key2');
      expect(value1, isNull);
      expect(value2, isNull);
    });

    test('get multiple items', () async {
      await store.put('key1', 'value1', 60);
      await store.put('key2', 'value2', 60);
      final values = await store.many(['key1', 'key2', 'key3']);
      expect(values['key1'], 'value1');
      expect(values['key2'], 'value2');
      expect(values['key3'], isNull);
    });

    test('creates shallow directory structure with long keys', () async {
      // This test ensures that long keys like "dashboard:dev-tenant:default:definitions"
      // create a shallow hashed directory structure (e.g., ab/cd/hash) instead of
      // character-by-character directories (d/a/s/h/b/o/a/r/d/...)
      const longKey = 'dashboard:dev-tenant:default:definitions';
      await store.put(longKey, 'test-value', 60);

      // Verify the value was stored and can be retrieved
      final value = await store.get(longKey);
      expect(value, 'test-value');

      // Check directory depth - should be exactly 2 levels deep (e.g., ab/cd/hashfile)
      final entities = tempDir.listSync(recursive: true);
      final files = entities.whereType<File>().where(
        (f) => !f.path.contains('.lock'),
      );
      expect(files.length, 1);

      final file = files.first;
      final relativePath = file.path.replaceFirst('${tempDir.path}/', '');
      final pathParts = relativePath.split('/');

      // Should be: dir1/dir2/hashfile (3 parts total)
      expect(
        pathParts.length,
        3,
        reason:
            'Cache path should have 2 directory levels plus filename, got: $relativePath',
      );

      // Each directory level should be 2 characters (from hash)
      expect(pathParts[0].length, 2);
      expect(pathParts[1].length, 2);

      // Filename should be full SHA-1 hash (40 hex chars)
      expect(pathParts[2].length, 40);
    });

    test('getAllKeys returns original keys not hashes', () async {
      const key1 = 'dashboard:dev-tenant:default:definitions';
      const key2 = 'another:complex:cache:key';
      await store.put(key1, 'value1', 60);
      await store.put(key2, 'value2', 60);

      final keys = await store.getAllKeys();
      expect(keys, containsAll([key1, key2]));
      expect(keys.length, 2);
    });
  });
}
