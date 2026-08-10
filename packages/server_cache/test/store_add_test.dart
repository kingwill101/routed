import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:server_cache/server_cache.dart';
import 'package:test/test.dart';

/// Expires every cache file under [directory] by rewriting its payload with a
/// past expiry timestamp, simulating the passage of time on disk.
Future<void> expireAllFiles(Directory directory) async {
  final entities = directory
      .listSync(recursive: true)
      .whereType<io.File>()
      .toList();
  for (final file in entities) {
    final raw = file.readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    data['expiresAt'] = DateTime.now().millisecondsSinceEpoch - 1000;
    file.writeAsStringSync(jsonEncode(data));
  }
}

void main() {
  group('ArrayStore.add', () {
    test('stores only when the key is absent', () async {
      final store = ArrayStore();
      expect(await store.add('key', 'value', 0), isTrue);
      expect(await store.add('key', 'other', 0), isFalse,
          reason: 'add must not overwrite an unexpired value');
      expect(await store.get('key'), 'value');
    });

    test('allows a new value once the previous one expired', () async {
      final store = ArrayStore();
      expect(await store.add('key', 'value', 1), isTrue);
      // Push the stored expiry into the past so the entry is expired.
      final item = store.storage['key'] as Map<String, dynamic>;
      item['expiresAt'] = 1;
      expect(await store.add('key', 'replacement', 1), isTrue);
      expect(await store.get('key'), 'replacement');
    });
  });

  group('FileStore', () {
    test('entries expire after their TTL (ms comparison)', () async {
      final fs = MemoryFileSystem();
      final store = FileStore(fs.directory('/cache'), null, null, fs);
      store.put('key', 'value', 1);
      expect(await store.get('key'), 'value');

      final file = fs
          .directory('/cache')
          .listSync(recursive: true)
          .firstWhere((e) => e is io.File) as io.File;
      final data =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      // The stored expiry is a milliseconds epoch; a past value means expired.
      data['expiresAt'] = DateTime.now().millisecondsSinceEpoch - 1000;
      file.writeAsStringSync(jsonEncode(data));

      expect(await store.get('key'), isNull,
          reason: 'an expired entry must not be returned');
    });
  });

  group('FileStore.add', () {
    test('fails while an unexpired entry exists', () async {
      final fs = MemoryFileSystem();
      final store = FileStore(fs.directory('/cache'), null, null, fs);
      expect(store.add('key', 'value', 0), isTrue);
      expect(store.add('key', 'other', 0), isFalse,
          reason: 'add must not clobber an unexpired entry');
      expect(await store.get('key'), 'value');
    });

    test('re-acquires a slot once the entry has expired', () async {
      final fs = MemoryFileSystem();
      final store = FileStore(fs.directory('/cache'), null, null, fs);
      store.put('key', 'value', 1);
      await expireAllFiles(fs.directory('/cache'));
      expect(await store.get('key'), isNull);
      expect(store.add('key', 'replacement', 0), isTrue);
      expect(await store.get('key'), 'replacement');
    });
  });

  group('FileLock acquire', () {
    test('fails while another owner holds the lock', () async {
      final fs = MemoryFileSystem();
      final store = FileStore(fs.directory('/cache'), null, null, fs);
      final lock = await store.lock('critical', 60, 'process-a');
      expect(await lock.acquire(), isTrue);
      expect(await lock.getCurrentOwner(), 'process-a');

      final other = await store.restoreLock('critical', 'process-b');
      expect(await other.acquire(), isFalse,
          reason:
              'must not overwrite an unexpired lock held by another owner');
      expect(await lock.getCurrentOwner(), 'process-a');
    });

    test('can be acquired again once the lock expires', () async {
      final fs = MemoryFileSystem();
      final store = FileStore(fs.directory('/cache'), null, null, fs);
      final lock = await store.lock('critical', 1, 'process-a');
      expect(await lock.acquire(), isTrue);
      await expireAllFiles(fs.directory('/cache'));
      expect(await lock.acquire(), isTrue,
          reason: 'an expired lock file must be re-acquirable');
    });
  });

  group('RepositoryImpl.add', () {
    test('second add for the same key reports false', () async {
      final store = ArrayStore();
      final repository = RepositoryImpl(store, 'default', '');
      expect(
          await repository.add('key', 'value', const Duration(seconds: 10)),
          isTrue);
      expect(
          await repository.add('key', 'other', const Duration(seconds: 10)),
          isFalse,
          reason: 'repository add must be store-only-if-absent');
      expect(await repository.get('key'), 'value');
    });
  });

  group('TagSet', () {
    test('resolves tag ids asynchronously from the store', () async {
      final store = ArrayStore();
      final tags = TagSet(store, ['user', 'session']);
      final namespace = await tags.getNamespace();
      expect(namespace, contains('|'));
      final ids = await tags.tagIds();
      expect(ids, hasLength(2));
      expect(await tags.getNamespace(), namespace,
          reason: 'tag ids persist, so the namespace must be stable');
    });

    test('resetTag changes the namespace', () async {
      final store = ArrayStore();
      final tags = TagSet(store, ['user']);
      final before = await tags.getNamespace();
      await tags.resetTag('user');
      expect(await tags.getNamespace(), isNot(before));
    });
  });

  group('TaggedCache namespacing', () {
    test('keys are scoped by tag namespace', () async {
      final store = ArrayStore();
      final cached = store.tags(['user']);
      await cached.put('profile', 'alice', const Duration(minutes: 5));
      expect(await store.get('profile'), isNull,
          reason: 'raw key must not be used; only the namespaced key is set');
      expect(await cached.get('profile'), 'alice');
    });

    test('different tag namespaces do not collide', () async {
      final store = ArrayStore();
      final userCache = store.tags(['user']);
      final adminCache = store.tags(['admin']);
      await userCache.put('dashboard', 'user-data');
      await adminCache.put('dashboard', 'admin-data');
      expect(await userCache.get('dashboard'), 'user-data');
      expect(await adminCache.get('dashboard'), 'admin-data');
    });

    test('resetting a tag invalidates previously cached values', () async {
      final store = ArrayStore();
      final cache = store.tags(['user']);
      await cache.put('profile', 'alice', const Duration(minutes: 5));
      expect(await cache.get('profile'), 'alice');
      await cache.getTags().resetTag('user');
      expect(await cache.get('profile'), isNull,
          reason: 'namespace changed, so the old value must be unreachable');
    });
  });
}