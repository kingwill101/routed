import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/contracts/cache/repository.dart' as cache;
import 'package:routed/src/contracts/cache/store.dart' as cache_store;
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

class _InMemoryRepository implements cache.Repository {
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
  cache_store.Store getStore() {
    throw UnimplementedError();
  }
}

Map<String, List<String>> _cookieHeader(Cookie cookie) {
  return {
    HttpHeaders.cookieHeader: ['${cookie.name}=${cookie.value}'],
  };
}

Map<String, List<String>> _cookieHeaderValue(String name, String value) {
  return {
    HttpHeaders.cookieHeader: ['$name=$value'],
  };
}

void main() {
  group('Session model', () {
    test('serializes, deserializes, and converts values', () {
      final options = Options(path: '/app', maxAge: 60);
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

  group('Session options', () {
    test('clones and serializes options', () {
      final options = Options(
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
      final restored = Options.fromJson(json);
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
        Hmac(
          sha256,
          base64.decode(key.replaceFirst('base64:', '')),
        ).convert(utf8.encode(payload)).bytes,
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
    engineTest(
      'writes, reads, and handles missing sessions',
      (engine, client) async {
        final codec = SecureCookie(key: SecureCookie.generateKey());
        final store = MemorySessionStore(
          codecs: [codec],
          defaultOptions: Options(maxAge: 5),
        );

        engine.get('/write', (ctx) async {
          final session = Session(name: 'mem', options: Options(maxAge: 5));
          session.setValue('foo', 'bar');
          await store.write(ctx.request, ctx.response, session);
          return ctx.response;
        });
        engine.get('/read', (ctx) async {
          final loaded = await store.read(ctx.request, 'mem');
          return ctx.json({
            'id': loaded.id,
            'foo': loaded.values['foo'],
            'isNew': loaded.isNew,
          });
        });

        final writeResponse = await client.get('/write');
        final cookie = writeResponse.cookie('mem');
        expect(cookie, isNotNull);

        final readResponse = await client.get(
          '/read',
          headers: _cookieHeader(cookie!),
        );
        expect(readResponse.json()['foo'], equals('bar'));
        expect(readResponse.json()['isNew'], isFalse);

        final orphanPayload = codec.encode('mem', {'id': 'missing'});
        final orphanResponse = await client.get(
          '/read',
          headers: _cookieHeaderValue(
            'mem',
            Uri.encodeComponent(orphanPayload),
          ),
        );
        expect(orphanResponse.json()['id'], equals('missing'));
        expect(orphanResponse.json()['isNew'], isFalse);
      },
      transportMode: TransportMode.ephemeralServer,
    );
  });

  group('CacheSessionStore', () {
    engineTest(
      'reads from cache and parses nested ids',
      (engine, client) async {
        final repo = _InMemoryRepository();
        final codec = SecureCookie(key: SecureCookie.generateKey());
        final store = CacheSessionStore(
          repository: repo,
          codecs: [codec],
          defaultOptions: Options(maxAge: 10),
        );

        engine.get('/write', (ctx) async {
          final session = Session(name: 'cache', options: Options(maxAge: 10));
          session.setValue('token', 'abc');
          await store.write(ctx.request, ctx.response, session);
          return ctx.response;
        });
        engine.get('/read', (ctx) async {
          final loaded = await store.read(ctx.request, 'cache');
          return ctx.json({
            'id': loaded.id,
            'token': loaded.values['token'],
            'isNew': loaded.isNew,
          });
        });

        final writeResponse = await client.get('/write');
        expect(repo.entries.values, isNotEmpty);

        final cookie = writeResponse.cookie('cache');
        expect(cookie, isNotNull);

        final readResponse = await client.get(
          '/read',
          headers: _cookieHeader(cookie!),
        );
        expect(readResponse.json()['token'], equals('abc'));
        expect(readResponse.json()['isNew'], isFalse);

        final nestedPayload = codec.encode('cache', {
          'data': jsonEncode({'id': 'nested'}),
        });
        final nestedResponse = await client.get(
          '/read',
          headers: _cookieHeaderValue(
            'cache',
            Uri.encodeComponent(nestedPayload),
          ),
        );
        expect(nestedResponse.json()['id'], equals('nested'));
        expect(nestedResponse.json()['isNew'], isFalse);

        repo.entries['session:nested'] = 'invalid-json';
        final corruptedResponse = await client.get(
          '/read',
          headers: _cookieHeaderValue(
            'cache',
            Uri.encodeComponent(nestedPayload),
          ),
        );
        expect(corruptedResponse.json()['id'], equals('nested'));
        expect(corruptedResponse.json()['isNew'], isFalse);
      },
      transportMode: TransportMode.ephemeralServer,
    );

    engineTest(
      'clears cache when session is destroyed',
      (engine, client) async {
        final repo = _InMemoryRepository();
        final store = CacheSessionStore(
          repository: repo,
          codecs: [SecureCookie(key: SecureCookie.generateKey())],
          defaultOptions: Options(maxAge: 10),
        );

        engine.get('/destroy', (ctx) async {
          final session = Session(name: 'cache', options: Options(maxAge: 10));
          await store.write(ctx.request, ctx.response, session);

          session.destroy();
          session.id = 'dead-session';
          repo.entries['session:dead-session'] = 'payload';

          await store.write(ctx.request, ctx.response, session);
          return ctx.json({
            'hasEntry': repo.entries.containsKey('session:dead-session'),
          });
        });

        final response = await client.get('/destroy');
        expect(response.json()['hasEntry'], isFalse);
      },
      transportMode: TransportMode.ephemeralServer,
    );
  });

  group('FilesystemStore', () {
    engineTest(
      'persists sessions and prunes expired files',
      (engine, client) async {
        final fs = MemoryFileSystem();
        final directory = fs.systemTempDirectory.createTempSync('sessions');
        final codec = SecureCookie(key: SecureCookie.generateKey());
        final store = FilesystemStore(
          storageDir: directory.path,
          codecs: [codec],
          defaultOptions: Options(maxAge: 1),
          lottery: const [1, 1],
          fileSystem: fs,
        );

        final oldFile = fs.file(fs.path.join(directory.path, 'session_old'));
        await oldFile.writeAsString(jsonEncode({'stale': true}));
        await oldFile.setLastModified(
          DateTime.now().subtract(const Duration(seconds: 10)),
        );

        engine.get('/write', (ctx) async {
          final session = Session(
            name: 'file',
            options: Options(maxAge: 10, path: '/'),
          );
          session.setValue('user', 'alice');
          await store.write(ctx.request, ctx.response, session);
          return ctx.response;
        });
        engine.get('/read', (ctx) async {
          final loaded = await store.read(ctx.request, 'file');
          return ctx.json({
            'user': loaded.values['user'],
            'isNew': loaded.isNew,
          });
        });

        addTearDown(() async {
          await directory.delete(recursive: true);
        });

        final writeResponse = await client.get('/write');
        expect(await oldFile.exists(), isFalse);

        final cookie = writeResponse.cookie('file');
        expect(cookie, isNotNull);

        final readResponse = await client.get(
          '/read',
          headers: _cookieHeader(cookie!),
        );
        expect(readResponse.json()['user'], equals('alice'));
        expect(readResponse.json()['isNew'], isFalse);
      },
      transportMode: TransportMode.ephemeralServer,
    );

    engineTest(
      'erases file when session expires',
      (engine, client) async {
        final fs = MemoryFileSystem();
        final directory = fs.systemTempDirectory.createTempSync('sessions');
        final store = FilesystemStore(
          storageDir: directory.path,
          codecs: [SecureCookie(key: SecureCookie.generateKey())],
          defaultOptions: Options(maxAge: 0),
          fileSystem: fs,
        );

        engine.get('/write', (ctx) async {
          final session = Session(
            name: 'file',
            options: Options(maxAge: 0, path: '/'),
          );
          await store.write(ctx.request, ctx.response, session);
          return ctx.response;
        });

        addTearDown(() async {
          await directory.delete(recursive: true);
        });

        final response = await client.get('/write');
        final cookie = response.cookie('file');
        expect(cookie, isNotNull);
        expect(cookie!.maxAge, equals(-1));
      },
      transportMode: TransportMode.ephemeralServer,
    );
  });
}
