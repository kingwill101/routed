import 'dart:io';

import 'package:file/memory.dart';
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_sessions/server_sessions.dart';
import 'package:test/test.dart';

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
  Future<dynamic> pull(key, [defaultValue]) => throw UnimplementedError();

  @override
  Future<bool> add(String key, value, [Duration? ttl]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> increment(String key, [value = 1]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> decrement(String key, [value = 1]) =>
      throw UnimplementedError();

  @override
  Future<bool> forever(String key, value) => throw UnimplementedError();

  @override
  Future<dynamic> remember(String key, ttl, Function callback) =>
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

class _MockRequest implements SessionRequest {
  @override
  final List<Cookie> cookies;
  _MockRequest({List<Cookie>? cookies}) : cookies = cookies ?? [];
  @override
  String header(String name) => '';
}

class _MockResponse implements SessionResponse {
  final Map<String, Cookie> cookies = {};
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

void main() {
  group('SessionRuntimeFactory integration', () {
    test('configures cookie driver with extended options', () async {
      const factory = SessionRuntimeFactory();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final options = SessionOptions(
        path: '/app',
        maxAge: 90 * 60,
        secure: false,
        httpOnly: false,
        sameSite: SameSite.strict,
      );

      final store = factory.cookie(codecs: [codec]);
      expect(store, isA<CookieStore>());
      expect(store.defaultOptions.path, equals('/'));
      // Verify custom options can be used with session
      final session = Session(name: 'demo_session', options: options);
      final req = _MockRequest();
      final res = _MockResponse();
      await store.write(req, res, session);
      expect(res.cookies.containsKey('demo_session'), isTrue);
    });

    test('configures file driver with lottery', () async {
      final fs = MemoryFileSystem();
      final temp = fs.systemTempDirectory.createTempSync('session_store');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      const factory = SessionRuntimeFactory();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = factory.file(
        codecs: [codec],
        storagePath: temp.path,
        defaultOptions: SessionOptions(path: '/app', secure: true, maxAge: 3600),
        lottery: const [1, 2],
        fileSystem: fs,
      );

      expect(store, isA<FilesystemStore>());
      String normalizePath(String value) => value.replaceAll('\\', '/');
      expect(normalizePath(store.storageDir), equals(normalizePath(temp.path)));
      expect(store.lottery, equals([1, 2]));
      expect(store.defaultOptions.path, equals('/app'));
      expect(store.defaultOptions.secure, isTrue);
    });

    test('configures cache-backed driver using repository', () async {
      final repo = _InMemoryRepository();
      const factory = SessionRuntimeFactory();
      final store = factory.cache(
        repository: repo,
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(
          path: '/',
          sameSite: SameSite.none,
          maxAge: 3600,
        ),
        cachePrefix: 'sess:',
        lifetime: const Duration(hours: 2),
      );

      expect(store, isA<CacheSessionStore>());
      expect(store.cachePrefix, equals('sess:'));
      expect(store.defaultOptions.sameSite, equals(SameSite.none));
    });

    test('configures array/memory driver with in-memory store', () async {
      const factory = SessionRuntimeFactory();
      final store = factory.memory(
        codecs: [SecureCookie(key: SecureCookie.generateKey())],
        defaultOptions: SessionOptions(maxAge: 30 * 60, httpOnly: true),
        lifetime: const Duration(minutes: 30),
      );

      expect(store, isA<MemorySessionStore>());
      expect(store.defaultOptions.maxAge, equals(30 * 60));
      expect(store.defaultOptions.httpOnly, isTrue);
      expect(store.lifetime, equals(const Duration(minutes: 30)));
    });

    test('throws when no codecs provided to CookieStore', () {
      expect(
        () => CookieStore(codecs: []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('memory store uses default codec when empty list provided', () {
      final store = MemorySessionStore(
        codecs: [],
        defaultOptions: SessionOptions(maxAge: 3600),
      );
      expect(store.codecs, isNotEmpty);
    });

    test('rebuilds store with new options (simulates config reload)', () async {
      const factory = SessionRuntimeFactory();
      final codec = SecureCookie(key: SecureCookie.generateKey());

      // Initial config: cookie driver
      final initialStore = factory.cookie(codecs: [codec]);
      expect(initialStore, isA<CookieStore>());

      // Simulate config reload to memory driver
      final reloadedStore = factory.memory(
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 600, httpOnly: false),
        lifetime: const Duration(minutes: 10),
      );
      expect(reloadedStore, isA<MemorySessionStore>());
      expect(reloadedStore.defaultOptions.maxAge, equals(600));
      expect(reloadedStore.defaultOptions.httpOnly, isFalse);
    });

    test('file store isolates sessions by id', () async {
      final fs = MemoryFileSystem();
      final dir = fs.systemTempDirectory.createTempSync('sessions-isolation-');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      const factory = SessionRuntimeFactory();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = factory.file(
        codecs: [codec],
        storagePath: dir.path,
        defaultOptions: SessionOptions(maxAge: 3600),
        fileSystem: fs,
      );

      final req1 = _MockRequest();
      final res1 = _MockResponse();
      final s1 = Session(name: 'file', options: SessionOptions(maxAge: 3600, path: '/'));
      s1.setValue('user', 'alice');
      await store.write(req1, res1, s1);

      final cookie1 = res1.cookies['file']!;
      final req2 = _MockRequest(cookies: [Cookie('file', cookie1.value)]);
      final loaded = await store.read(req2, 'file');
      expect(loaded.values['user'], equals('alice'));

      // Different session should be isolated
      final s2 = Session(name: 'file', options: SessionOptions(maxAge: 3600, path: '/'));
      s2.setValue('user', 'bob');
      final req3 = _MockRequest();
      final res3 = _MockResponse();
      await store.write(req3, res3, s2);
      final cookie2 = res3.cookies['file']!;
      expect(cookie2.value, isNot(equals(cookie1.value)));
    });

    test('documents session options paths', () {
      final options = SessionOptions(
        path: '/api',
        domain: 'example.com',
        maxAge: 3600,
        secure: true,
        httpOnly: true,
        sameSite: SameSite.lax,
        partitioned: false,
      );
      final json = options.toJson();
      expect(json.containsKey('path'), isTrue);
      expect(json.containsKey('domain'), isTrue);
      expect(json.containsKey('maxAge'), isTrue);
      expect(json.containsKey('secure'), isTrue);
      expect(json.containsKey('httpOnly'), isTrue);
      expect(json.containsKey('sameSite'), isTrue);
      expect(json.containsKey('partitioned'), isTrue);
    });

    test('secure cookies support all modes', () {
      final key = SecureCookie.generateKey();
      final hmac = SecureCookie(key: key, mode: SecurityMode.hmacOnly);
      final aes = SecureCookie(key: key, mode: SecurityMode.aesOnly);
      final both = SecureCookie(key: key, mode: SecurityMode.both);

      final payload = {'test': 'value', 'num': 42};

      expect(hmac.decode('s', hmac.encode('s', payload))['test'], equals('value'));
      expect(aes.decode('s', aes.encode('s', payload))['test'], equals('value'));
      expect(both.decode('s', both.encode('s', payload))['test'], equals('value'));
    });

    test('session regenerates and destroys correctly', () {
      final session = Session(
        name: 'test',
        options: SessionOptions(maxAge: 3600),
        values: {'key': 'value'},
      );
      final originalId = session.id;
      session.regenerate();
      expect(session.id, isNot(equals(originalId)));
      expect(session.values['key'], equals('value'));

      session.destroy();
      expect(session.isDestroyed, isTrue);
      expect(session.values, isEmpty);
      expect(session.options.maxAge, equals(0));
    });
  });
}
