import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_data/server_data.dart';
import 'package:test/test.dart';

class _FakeSessionRequest implements SessionRequest {
  _FakeSessionRequest({List<Cookie>? cookies, Map<String, String>? headers})
    : cookies = cookies ?? <Cookie>[],
      _headers = headers ?? <String, String>{};

  @override
  final List<Cookie> cookies;

  final Map<String, String> _headers;

  @override
  String header(String name) => _headers[name] ?? '';
}

class _FakeSessionResponse implements SessionResponse {
  final List<Cookie> cookies = <Cookie>[];

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
    final cookie = Cookie(name, value.toString())
      ..maxAge = maxAge
      ..path = path
      ..secure = secure
      ..httpOnly = httpOnly
      ..sameSite = sameSite;
    if (domain.isNotEmpty) {
      cookie.domain = domain;
    }
    cookies.removeWhere((c) => c.name == name);
    cookies.add(cookie);
  }
}

class _InMemoryRepository implements contracts.Repository {
  final Map<String, dynamic> entries = <String, dynamic>{};

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

void main() {
  group('session model', () {
    test('serializes and deserializes', () {
      final options = SessionOptions(path: '/app', maxAge: 60);
      final session = Session(
        id: 'session-id',
        name: 'session',
        options: options,
        values: {'count': 3},
      )..isNew = false;

      session.setValue('name', 'server-data');
      final restored = Session.deserialize(session.serialize());

      expect(restored.id, equals('session-id'));
      expect(restored.options.path, equals('/app'));
      expect(restored.values['name'], equals('server-data'));
      expect(restored.isNew, isFalse);
    });

    test('session options clone and json', () {
      final options = SessionOptions(
        path: '/api',
        domain: 'example.com',
        maxAge: 120,
        secure: true,
        httpOnly: false,
        partitioned: true,
        sameSite: SameSite.strict,
      );

      final restored = SessionOptions.fromJson(options.toJson());
      final copied = options.copyWith(path: '/new', maxAge: 10);

      expect(restored.path, equals('/api'));
      expect(restored.maxAge, equals(120));
      expect(copied.path, equals('/new'));
      expect(copied.maxAge, equals(10));
    });

    test('secure cookie encodes and decodes', () {
      const key = 'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      final codec = SecureCookie(key: key, mode: SecurityMode.both);

      final encoded = codec.encode('session', {'flag': true});
      final decoded = codec.decode('session', encoded);

      expect(decoded['flag'], isTrue);
    });
  });

  group('session stores', () {
    test('memory store writes and reads', () async {
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = MemorySessionStore(
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 5),
      );

      final request = _FakeSessionRequest();
      final response = _FakeSessionResponse();
      final session = Session(name: 'mem', options: SessionOptions(maxAge: 5));
      session.setValue('foo', 'bar');

      await store.write(request, response, session);
      final cookie = response.cookies.firstWhere((c) => c.name == 'mem');

      final loaded = await store.read(
        _FakeSessionRequest(cookies: [cookie]),
        'mem',
      );
      expect(loaded.values['foo'], equals('bar'));
      expect(loaded.isNew, isFalse);
    });

    test('cache store writes and reads', () async {
      final repo = _InMemoryRepository();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = CacheSessionStore(
        repository: repo,
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 10),
      );

      final request = _FakeSessionRequest();
      final response = _FakeSessionResponse();
      final session = Session(
        name: 'cache',
        options: SessionOptions(maxAge: 10),
      );
      session.setValue('token', 'abc');

      await store.write(request, response, session);
      final cookie = response.cookies.firstWhere((c) => c.name == 'cache');

      final loaded = await store.read(
        _FakeSessionRequest(cookies: [cookie]),
        'cache',
      );
      expect(loaded.values['token'], equals('abc'));
    });

    test('cookie store round-trips payload', () async {
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = CookieStore(codecs: [codec]);
      final request = _FakeSessionRequest();
      final response = _FakeSessionResponse();
      final session = Session(
        name: 'cookie',
        options: SessionOptions(maxAge: 120),
        values: {'name': 'alice'},
      )..isNew = false;

      await store.write(request, response, session);
      final cookie = response.cookies.firstWhere((c) => c.name == 'cookie');

      final loaded = await store.read(
        _FakeSessionRequest(
          cookies: [cookie],
          headers: {HttpHeaders.cookieHeader: 'cookie=${cookie.value}'},
        ),
        'cookie',
      );

      expect(loaded.values['name'], equals('alice'));
    });

    test('filesystem store persists data', () async {
      final fs = MemoryFileSystem();
      final dir = fs.systemTempDirectory.createTempSync('sessions');
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = FilesystemStore(
        storageDir: dir.path,
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 300),
        fileSystem: fs,
      );

      final response = _FakeSessionResponse();
      final session = Session(
        name: 'file',
        options: SessionOptions(maxAge: 300),
        values: {'k': 'v'},
      )..isNew = false;

      await store.write(_FakeSessionRequest(), response, session);
      final cookie = response.cookies.firstWhere((c) => c.name == 'file');

      final loaded = await store.read(
        _FakeSessionRequest(cookies: [cookie]),
        'file',
      );
      expect(loaded.values['k'], equals('v'));

      dir.deleteSync(recursive: true);
    });

    test('cache store decodes nested id payload', () async {
      final repo = _InMemoryRepository();
      final codec = SecureCookie(key: SecureCookie.generateKey());
      final store = CacheSessionStore(
        repository: repo,
        codecs: [codec],
        defaultOptions: SessionOptions(maxAge: 10),
      );
      final payload = codec.encode('cache', {
        'data': jsonEncode({'id': 'nested'}),
      });
      final cookie = Cookie('cache', Uri.encodeComponent(payload));

      final loaded = await store.read(
        _FakeSessionRequest(cookies: [cookie]),
        'cache',
      );

      expect(loaded.id, equals('nested'));
      expect(loaded.isNew, isFalse);
    });
  });
}
