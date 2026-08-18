import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file/memory.dart';
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_sessions/server_sessions.dart';
import 'package:test/test.dart';

// Lightweight in-memory Repository for CacheSessionStore tests.
class _InMemoryRepository implements contracts.Repository {
  final Map<String, dynamic> entries = {};

  @override
  Future<dynamic> get(String key) async => entries[key];

  @override
  Future<bool> put(String key, value, [Duration? ttl]) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> forget(String key) async {
    entries.remove(key);
    return true;
  }

  @override
  Future<dynamic> pull(key, [defaultValue]) {
    throw UnimplementedError();
  }

  @override
  Future<bool> add(String key, value, [Duration? ttl]) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> increment(String key, [value = 1]) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> decrement(String key, [value = 1]) {
    throw UnimplementedError();
  }

  @override
  Future<bool> forever(String key, value) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> remember(String key, ttl, Function callback) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> sear(String key, Function callback) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> rememberForever(String key, Function callback) {
    throw UnimplementedError();
  }

  @override
  contracts.Store getStore() {
    throw UnimplementedError();
  }
}

class _MockRequest implements SessionRequest {
  @override
  final List<Cookie> cookies;
  final Map<String, String> _headers;

  _MockRequest({List<Cookie>? cookies, Map<String, String>? headers})
      : cookies = cookies ?? [],
        _headers = headers ?? {};

  @override
  String header(String name) => _headers[name] ?? '';
}

class _MockResponse implements SessionResponse {
  final Map<String, Cookie> cookies = {};

  Cookie? cookie(String name) => cookies[name];

  @override
  void setCookie(
    String name,
    dynamic value, {
    int? maxAge,
    String path = '/',
    String domain = '',
    bool secure = false,
    bool httpOnly = false,
    SameSite? sameSite,
  }) {
    final c = Cookie(name, value.toString());
    if (maxAge != null) c.maxAge = maxAge;
    c.path = path;
    c.domain = domain;
    c.secure = secure;
    c.httpOnly = httpOnly;
    if (sameSite != null) c.sameSite = sameSite;
    cookies[name] = c;
  }
}

List<int> _hmacSha256(List<int> key, List<int> message) {
  final hmac = crypto.Hmac(crypto.sha256, key);
  return hmac.convert(message).bytes;
}

void main() {
  group('Session model', () {
    test('serializes, deserializes, and converts values', () {
      final options = SessionOptions(path: '/app', maxAge: 60);
      final createdAt = DateTime.utc(2024, 1, 1);
      final accessedAt = DateTime.utc(2024, 1, 2);
      final session = Session(
        id: 'session-id',
        name: 'session',
        options: options,
        values: {'count': 3},
        createdAt: createdAt,
        lastAccessed: accessedAt,
      );
      session.isNew = false;

      session.setValue('name', 'routed');
      expect(session.getValue<int>('count'), equals(3));
      expect(session.getValue<String>('count'), equals('3'));
      expect(session.getValue<int>('missing'), isNull);

      final serialized = session.serialize();
      final restored = Session.deserialize(serialized);

      expect(restored.id, equals('session-id'));
      expect(restored.name, equals('session'));
      expect(restored.options.path, equals('/app'));
      expect(restored.values['name'], equals('routed'));
      expect(restored.createdAt, equals(createdAt));
      expect(restored.lastAccessed.isAfter(accessedAt), isTrue);
      expect(restored.isNew, isFalse);

      restored.regenerate();
      expect(restored.id, isNot(equals('session-id')));
      expect(restored.isNew, isFalse);

      restored.destroy();
      expect(restored.isDestroyed, isTrue);
      expect(restored.values, isEmpty);
      expect(restored.options.maxAge, equals(0));
    });
  });

  group('SessionOptions', () {
    test('clones and serializes options', () {
      final options = SessionOptions(
        path: '/api',
        domain: 'example.com',
        maxAge: 120,
        secure: true,
        httpOnly: false,
        partitioned: true,
        sameSite: SameSite.strict,
      );
      options.setMaxAge(240);

      final json = options.toJson();
      final restored = SessionOptions.fromJson(json);
      final cloned = options.clone();
      final copied = options.copyWith(path: '/new', maxAge: 10);

      expect(restored.path, equals('/api'));
      expect(restored.maxAge, equals(240));
      expect(cloned.domain, equals('example.com'));
      expect(copied.path, equals('/new'));
      expect(copied.maxAge, equals(10));
    });
  });

  group('SecureCookie', () {
    const key = 'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

    test('encodes and decodes with HMAC-only mode', () {
      final cookie = SecureCookie(key: key, mode: SecurityMode.hmacOnly);
      final encoded = cookie.encode('session', {'user': 'routed'});
      final decoded = cookie.decode('session', encoded);

      expect(decoded['user'], equals('routed'));

      final payload = jsonEncode(['one', 'two']);
      final signature = base64Url.encode(
        _hmacSha256(
          base64.decode(key.replaceFirst('base64:', '')),
          utf8.encode('session|$payload'),
        ),
      );
      final custom = base64Url.encode(utf8.encode('$payload|$signature'));
      final decodedList = cookie.decode('session', custom);
      expect(decodedList['value'], isA<List<dynamic>>());

      final lastChar = encoded.substring(encoded.length - 1);
      final tampered =
          encoded.substring(0, encoded.length - 1) +
          (lastChar == 'A' ? 'B' : 'A');
      expect(
        () => cookie.decode('session', tampered),
        throwsA(isA<Exception>()),
      );
    });

    test('encodes and decodes with AES-only mode', () {
      final cookie = SecureCookie(key: key, mode: SecurityMode.aesOnly);
      final encoded = cookie.encode('session', {'role': 'admin'});
      final decoded = cookie.decode('session', encoded);

      expect(decoded['role'], equals('admin'));
    });

    test('encodes and decodes with combined mode', () {
      final cookie = SecureCookie(key: key, mode: SecurityMode.both);
      final encoded = cookie.encode('session', {'flag': true});
      final decoded = cookie.decode('session', encoded);

      expect(decoded['flag'], isTrue);
    });
  });

  group('MemorySessionStore', () {
    test('writes, reads, and handles missing sessions', () async {
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = MemorySessionStore(
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 5),
      );

      // Write
      final writeReq = _MockRequest();
      final writeRes = _MockResponse();
      final session = Session(name: 'mem', options: SessionOptions(maxAge: 5));
      session.setValue('foo', 'bar');
      await store.write(writeReq, writeRes, session);
      final cookie = writeRes.cookie('mem');
      expect(cookie, isNotNull);

      // Read
      final readReq = _MockRequest(cookies: [Cookie('mem', cookie!.value)]);
      final loaded = await store.read(readReq, 'mem');
      expect(loaded.values['foo'], equals('bar'));
      expect(loaded.isNew, isFalse);
      expect(loaded.id, isNotEmpty);

      // Orphan (missing store entry but valid cookie)
      final orphanPayload = codec.encode('mem', {'id': 'missing'});
      final orphanReq = _MockRequest(
        cookies: [Cookie('mem', Uri.encodeComponent(orphanPayload))],
      );
      final orphan = await store.read(orphanReq, 'mem');
      expect(orphan.id, equals('missing'));
      expect(orphan.isNew, isFalse);
    });
  });

  group('CacheSessionStore', () {
    test('reads from cache and parses nested ids', () async {
      final repo = _InMemoryRepository();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = CacheSessionStore(
        repository: repo,
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 10),
      );

      // Write
      final session = Session(name: 'cache', options: SessionOptions(maxAge: 10));
      session.setValue('token', 'abc');
      final writeReq = _MockRequest();
      final writeRes = _MockResponse();
      await store.write(writeReq, writeRes, session);
      expect(repo.entries.values, isNotEmpty);
      final cookie = writeRes.cookie('cache');
      expect(cookie, isNotNull);

      // Read
      final readReq = _MockRequest(cookies: [Cookie('cache', cookie!.value)]);
      final loaded = await store.read(readReq, 'cache');
      expect(loaded.values['token'], equals('abc'));
      expect(loaded.isNew, isFalse);

      // Nested id payload
      final nestedPayload = codec.encode('cache', {
        'data': jsonEncode({'id': 'nested'}),
      });
      final nestedReq = _MockRequest(
        cookies: [Cookie('cache', Uri.encodeComponent(nestedPayload))],
      );
      final nested = await store.read(nestedReq, 'cache');
      expect(nested.id, equals('nested'));
      expect(nested.isNew, isFalse);

      // Corrupted cache entry should still return session with id
      repo.entries['session:nested'] = 'invalid-json';
      final corrupted = await store.read(nestedReq, 'cache');
      expect(corrupted.id, equals('nested'));
      expect(corrupted.isNew, isFalse);
    });

    test('clears cache when session is destroyed', () async {
      final repo = _InMemoryRepository();
      final store = CacheSessionStore(
        repository: repo,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 10),
      );

      final session = Session(name: 'cache', options: SessionOptions(maxAge: 10));
      final req = _MockRequest();
      final res = _MockResponse();
      await store.write(req, res, session);

      session.destroy();
      session.id = 'dead-session';
      repo.entries['session:dead-session'] = 'payload';

      final destroyRes = _MockResponse();
      await store.write(req, destroyRes, session);
      expect(repo.entries.containsKey('session:dead-session'), isFalse);
      expect(destroyRes.cookie('cache'), isNotNull);
      expect(destroyRes.cookie('cache')!.maxAge, equals(0));
    });
  });

  group('FilesystemStore', () {
    test('persists sessions and prunes expired files', () async {
      final fs = MemoryFileSystem();
      final directory = fs.systemTempDirectory.createTempSync('sessions');
      addTearDown(() async {
        await directory.delete(recursive: true);
      });
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = FilesystemStore(
        storageDir: directory.path,
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 1),
        lottery: const [1, 1],
        fileSystem: fs,
      );

      final oldFile = fs.file(fs.path.join(directory.path, 'session_old'));
      await oldFile.writeAsString(jsonEncode({'stale': true}));
      await oldFile.setLastModified(
        DateTime.now().subtract(const Duration(seconds: 10)),
      );

      // Write
      final writeReq = _MockRequest();
      final writeRes = _MockResponse();
      final session = Session(
        name: 'file',
        options: SessionOptions(maxAge: 10, path: '/'),
      );
      session.setValue('user', 'alice');
      await store.write(writeReq, writeRes, session);
      expect(await oldFile.exists(), isFalse);

      final cookie = writeRes.cookie('file');
      expect(cookie, isNotNull);

      // Read
      final readReq = _MockRequest(cookies: [Cookie('file', cookie!.value)]);
      final loaded = await store.read(readReq, 'file');
      expect(loaded.values['user'], equals('alice'));
      expect(loaded.isNew, isFalse);
    });

    test('erases file when session expires', () async {
      final fs = MemoryFileSystem();
      final directory = fs.systemTempDirectory.createTempSync('sessions');
      addTearDown(() async {
        await directory.delete(recursive: true);
      });
      final store = FilesystemStore(
        storageDir: directory.path,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: -1),
        fileSystem: fs,
      );

      final writeReq = _MockRequest();
      final writeRes = _MockResponse();
      final session = Session(
        name: 'file',
        options: SessionOptions(maxAge: -1, path: '/'),
      );
      await store.write(writeReq, writeRes, session);
      final cookie = writeRes.cookie('file');
      expect(cookie, isNotNull);
      expect(cookie!.maxAge, equals(-1));
    });
  });
}
