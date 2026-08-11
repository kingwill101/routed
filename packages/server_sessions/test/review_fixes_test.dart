import 'dart:io';

import 'package:file/memory.dart';
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_sessions/server_sessions.dart';
import 'package:test/test.dart';

class _FakeRequest implements SessionRequest {
  @override
  final List<Cookie> cookies;

  final Map<String, String> headers = const {};

  _FakeRequest(this.cookies);

  @override
  String header(String name) => headers[name] ?? '';
}

class _FakeResponse implements SessionResponse {
  final List<(String, String, SetCookieParams)> cookies = [];

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
    cookies.add((
      name,
      value.toString(),
      SetCookieParams(maxAge, path, domain, secure, httpOnly, sameSite),
    ));
  }

  (String, String, SetCookieParams)? last(String name) {
    final matches = cookies.where((c) => c.$1 == name).toList();
    return matches.isEmpty ? null : matches.last;
  }
}

class SetCookieParams {
  final int? maxAge;
  final String path;
  final String domain;
  final bool secure;
  final bool httpOnly;
  final SameSite? sameSite;
  const SetCookieParams(
    this.maxAge,
    this.path,
    this.domain,
    this.secure,
    this.httpOnly,
    this.sameSite,
  );
}

class _FakeRepository implements contracts.Repository {
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
  Future<dynamic> pull(dynamic key, [dynamic defaultValue]) async {
    final value = entries[key];
    entries.remove(key);
    return value ?? defaultValue;
  }

  @override
  Future<bool> add(String key, dynamic value, [Duration? ttl]) async {
    final exists = entries.containsKey(key);
    if (!exists) entries[key] = value;
    return !exists;
  }

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final current = entries[key] as num? ?? 0;
    final next = current + (value as num);
    entries[key] = next;
    return next;
  }

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final current = entries[key] as num? ?? 0;
    final next = current - (value as num);
    entries[key] = next;
    return next;
  }

  @override
  Future<bool> forever(String key, dynamic value) =>
      put(key, value, null);

  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final value = entries[key];
    if (value != null) return value;
    final result = await callback();
    await put(key, result, ttl is Duration ? ttl : null);
    return result;
  }

  @override
  Future<dynamic> sear(String key, Function callback) =>
      rememberForever(key, callback);

  @override
  Future<dynamic> rememberForever(String key, Function callback) async {
    final value = entries[key];
    if (value != null) return value;
    final result = await callback();
    await put(key, result, null);
    return result;
  }

  @override
  contracts.Store getStore() => throw UnimplementedError();
}

List<SecureCookie> _codecs() => [
  SecureCookie(
    key: SecureCookie.generateKey(),
    useEncryption: true,
    useSigning: true,
  ),
];

void main() {
  group('Session destroy/regenerate retain previous ID', () {
    test('destroy keeps previousId and clears it from the store', () async {
      final repo = _FakeRepository();
      final store = CacheSessionStore(
        repository: repo,
        codecs: _codecs(),
        defaultOptions: SessionOptions(maxAge: 600),
        lifetime: const Duration(hours: 2),
      );
      final response = _FakeResponse();

      // Create and persist a session.
      final session = Session(
        name: 'sid',
        options: SessionOptions(maxAge: 600),
      );
      await store.write(_FakeRequest([]), response, session);
      final persistedId = session.id;
      expect(repo.entries, contains('session:$persistedId'));

      // Destroy it: the previous ID must be retained and the backend record
      // removed when write() runs.
      session.destroy();
      expect(session.previousId, persistedId);
      await store.write(_FakeRequest([]), response, session);
      expect(repo.entries, isNot(contains('session:$persistedId')),
          reason: 'server-side record referenced by the old cookie must go');
    });

    test('regenerate invalidates the old cache record on write', () async {
      final repo = _FakeRepository();
      final store = CacheSessionStore(
        repository: repo,
        codecs: _codecs(),
        defaultOptions: SessionOptions(maxAge: 600),
        lifetime: const Duration(hours: 2),
      );
      final response = _FakeResponse();

      final session = Session(
        name: 'sid',
        options: SessionOptions(maxAge: 600),
      );
      session.setValue('role', 'user');
      await store.write(_FakeRequest([]), response, session);
      final oldId = session.id;
      expect(repo.entries, contains('session:$oldId'));

      // Rotate the ID; the record under the old ID must be removed on write.
      session.regenerate();
      expect(session.previousId, oldId);
      await store.write(_FakeRequest([]), response, session);
      expect(repo.entries, isNot(contains('session:$oldId')));
      expect(repo.entries, contains('session:${session.id}'));
    });
  });

  group('CookieStore clones options per session', () {
    test('destroying one session does not mutate the store default', () async {
      final store = CookieStore(codecs: _codecs());
      final originalMaxAge = store.defaultOptions.maxAge;

      final first = await store.read(_FakeRequest([]), 'sid');
      first.destroy(); // previously mutated the shared defaultOptions
      expect(store.defaultOptions.maxAge, originalMaxAge,
          reason: 'destroy must not propagate maxAge=0 to the store default');

      final second = await store.read(_FakeRequest([]), 'sid');
      expect(second.options.maxAge, originalMaxAge,
          reason: 'new sessions must start from a pristine clone');
    });
  });

  group('FilesystemStore', () {
    test('persists non-expiring sessions (maxAge null)', () async {
      final fs = MemoryFileSystem();
      final store = FilesystemStore(
        storageDir: '/sessions',
        codecs: _codecs(),
        defaultOptions: SessionOptions(),
        fileSystem: fs,
      );
      final response = _FakeResponse();

      final session = Session(name: 'fsid', options: SessionOptions());
      session.setValue('user', 'alice');
      await store.write(_FakeRequest([]), response, session);
      final sid = session.id;

      // The session file must exist (previously the delete branch always ran
      // because maxAge null folded to 0 which was treated as deletion).
      final file = fs.file('/sessions/session_$sid');
      expect(await file.exists(), isTrue,
          reason: 'a default (non-expiring) session must be persisted');
      expect(response.last('fsid')?.$3.maxAge, isNull);
    });

    test('persists explicit maxAge 0 (documented as never expiring)', () async {
      final fs = MemoryFileSystem();
      final store = FilesystemStore(
        storageDir: '/sessions',
        codecs: _codecs(),
        defaultOptions: SessionOptions(),
        fileSystem: fs,
      );
      final response = _FakeResponse();

      final session = Session(
        name: 'fsid',
        options: SessionOptions(maxAge: 0),
      );
      session.setValue('user', 'bob');
      await store.write(_FakeRequest([]), response, session);
      expect(
        await fs.file('/sessions/session_${session.id}').exists(),
        isTrue,
      );
    });

    test('deleted sessions produce a cookie with the configured domain',
        () async {
      final fs = MemoryFileSystem();
      final store = FilesystemStore(
        storageDir: '/sessions',
        codecs: _codecs(),
        defaultOptions: SessionOptions(),
        fileSystem: fs,
      );
      final response = _FakeResponse();

      final session = Session(
        name: 'fsid',
        options: SessionOptions(domain: 'example.com'),
      );
      await store.write(_FakeRequest([]), response, session);
      final sid = session.id;

      session.destroy();
      await store.write(_FakeRequest([]), response, session);

      final cookie = response.last('fsid')!;
      expect(cookie.$3.maxAge, lessThan(0));
      expect(cookie.$3.domain, 'example.com',
          reason: 'deletion cookie must carry the same domain as creation');
      expect(await fs.file('/sessions/session_$sid').exists(), isFalse);
    });

    test('regenerate invalidates the old file', () async {
      final fs = MemoryFileSystem();
      final store = FilesystemStore(
        storageDir: '/sessions',
        codecs: _codecs(),
        defaultOptions: SessionOptions(),
        fileSystem: fs,
      );
      final response = _FakeResponse();

      final session = Session(name: 'fsid', options: SessionOptions());
      session.setValue('user', 'carol');
      await store.write(_FakeRequest([]), response, session);
      final oldId = session.id;
      expect(await fs.file('/sessions/session_$oldId').exists(), isTrue);

      session.regenerate();
      await store.write(_FakeRequest([]), response, session);
      expect(await fs.file('/sessions/session_$oldId').exists(), isFalse,
          reason: 'old cookie must no longer resolve after regeneration');
      expect(await fs.file('/sessions/session_${session.id}').exists(), isTrue);
    });
  });

  group('SecureCookie binds payloads to the cookie name', () {
    test('a value protected under one name is rejected under another',
        () async {
      final codec = SecureCookie(
        key: SecureCookie.generateKey(),
        useEncryption: true,
        useSigning: true,
      );
      final encoded = codec.encode('session_a', {'id': 'secret'});
      expect(() => codec.decode('session_b', encoded), throwsA(anything),
          reason: 'payload must not be accepted under a different cookie name');
      expect(codec.decode('session_a', encoded), {'id': 'secret'});
    });

    test('HMAC-only mode also binds the name', () async {
      final codec = SecureCookie(
        key: SecureCookie.generateKey(),
        useSigning: true,
        useEncryption: false,
      );
      final encoded = codec.encode('a', {'id': 'x'});
      expect(() => codec.decode('b', encoded), throwsA(anything));
      expect(codec.decode('a', encoded), {'id': 'x'});
    });

    test('AES-only mode also binds the name via authenticated data', () async {
      final codec = SecureCookie(
        key: SecureCookie.generateKey(),
        useEncryption: true,
        useSigning: false,
      );
      final encoded = codec.encode('alpha', {'id': 'y'});
      expect(() => codec.decode('beta', encoded), throwsA(anything));
      expect(codec.decode('alpha', encoded), {'id': 'y'});
    });
  });
}