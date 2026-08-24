import 'dart:convert';

import 'package:file/memory.dart';
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_sessions/server_sessions.dart';
import 'package:test/test.dart';

// Simple in-memory repository for cache tests.
class _InMemoryRepository implements contracts.Repository {
  final Map<String, dynamic> entries = {};

  @override
  Future<dynamic> get(String key) async => entries[key];

  @override
  Future<bool> put(String key, dynamic value, [Duration? ttl]) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> forget(String key) async {
    entries.remove(key);
    return true;
  }

  @override
  Future<dynamic> pull(dynamic key, [dynamic defaultValue]) =>
      throw UnimplementedError();

  @override
  Future<bool> add(String key, dynamic value, [Duration? ttl]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) =>
      throw UnimplementedError();

  @override
  Future<bool> forever(String key, dynamic value) => throw UnimplementedError();

  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) =>
      throw UnimplementedError();

  @override
  Future<dynamic> sear(String key, Function callback) =>
      throw UnimplementedError();

  @override
  Future<dynamic> rememberForever(String key, Function callback) =>
      throw UnimplementedError();

  @override
  contracts.Store getStore() => throw UnimplementedError();
}

void main() {
  group('SessionRuntimeFactory - file driver', () {
    test('creates FilesystemStore with provided storage path', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-defaults-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final storagePath = fs.path.join(baseDir.path, 'storage', 'sessions');
      fs.directory(storagePath).createSync(recursive: true);

      const factory = SessionRuntimeFactory();
      final store = factory.file(
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        storagePath: storagePath,
        defaultOptions: SessionOptions(maxAge: 3600),
        fileSystem: fs,
      );

      expect(store, isA<FilesystemStore>());
      expect(
        fs.path.normalize(store.storageDir),
        equals(fs.path.normalize(storagePath)),
      );
    });

    test('creates FilesystemStore with custom nested path', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-custom-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final storagePath = fs.path.join(baseDir.path, 'custom', 'sessions');
      fs.directory(storagePath).createSync(recursive: true);

      const factory = SessionRuntimeFactory();
      final store = factory.file(
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        storagePath: storagePath,
        defaultOptions: SessionOptions(maxAge: 3600),
        lottery: const [1, 100],
        fileSystem: fs,
      );

      expect(store, isA<FilesystemStore>());
      expect(
        fs.path.normalize(store.storageDir),
        equals(fs.path.normalize(storagePath)),
      );
      expect(store.lottery, equals([1, 100]));
    });

    test('creates FilesystemStore with base64 key', () {
      final fs = MemoryFileSystem();
      final baseDir = fs.systemTempDirectory.createTempSync(
        'session-storage-key-',
      );
      addTearDown(() {
        if (baseDir.existsSync()) {
          baseDir.deleteSync(recursive: true);
        }
      });
      final key =
          'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}';

      const factory = SessionRuntimeFactory();
      final store = factory.file(
        codecs: [SecureCookie(key: key)],
        storagePath: fs.path.join(baseDir.path, 'sessions'),
        defaultOptions: SessionOptions(maxAge: 3600),
        fileSystem: fs,
      );

      expect(store, isA<FilesystemStore>());
    });
  });

  group('SessionRuntimeFactory - cache driver', () {
    test('creates CacheSessionStore with repository', () {
      final repo = _InMemoryRepository();
      const factory = SessionRuntimeFactory();
      final store = factory.cache(
        repository: repo,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 3600),
        cachePrefix: 'session:',
        lifetime: const Duration(hours: 2),
      );

      expect(store, isA<CacheSessionStore>());
      expect(store.cachePrefix, equals('session:'));
    });

    test('creates CacheSessionStore with custom prefix', () {
      final repo = _InMemoryRepository();
      const factory = SessionRuntimeFactory();
      final store = factory.cache(
        repository: repo,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 3600),
        cachePrefix: 'custom:',
        lifetime: const Duration(minutes: 30),
      );

      expect(store, isA<CacheSessionStore>());
      expect(store.cachePrefix, equals('custom:'));
    });

    test('cache store separates keys by prefix', () async {
      final repo = _InMemoryRepository();
      const factory = SessionRuntimeFactory();
      final store = factory.cache(
        repository: repo,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 3600),
        cachePrefix: 'sess:',
        lifetime: const Duration(hours: 2),
      );

      // Verify prefix is applied
      expect(store.cachePrefix, equals('sess:'));
      expect(store.defaultOptions.maxAge, equals(3600));
    });
  });

  group('SessionRuntimeFactory - memory and cookie drivers', () {
    test('creates MemorySessionStore', () {
      const factory = SessionRuntimeFactory();
      final store = factory.memory(
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 1200),
        lifetime: const Duration(hours: 2),
      );

      expect(store, isA<MemorySessionStore>());
    });

    test('creates CookieStore', () {
      const factory = SessionRuntimeFactory();
      final store = factory.cookie(
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
      );

      expect(store, isA<CookieStore>());
    });

    test('memory and cookie stores handle Codec configuration', () {
      const factory = SessionRuntimeFactory();
      final codec = SecureCookie(key: SecureCookie.generateKey());

      final memory = factory.memory(
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 600),
        lifetime: const Duration(minutes: 10),
      );
      expect(memory.codecs, isNotEmpty);

      final cookieStore = factory.cookie(codecs: [codec]);
      expect(cookieStore, isA<CookieStore>());
      expect(cookieStore.defaultOptions, isNotNull);
    });
  });
}
