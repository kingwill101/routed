import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('PR A: foundation boundaries', () {
    test('Engine and EngineContext remain', () {
      final engine = Engine();
      expect(engine, isA<Engine>());
      // handler signature still valid
      FutureOr<Response> h(EngineContext ctx) => ctx.string('ok');
      expect(h, isA<Handler>());
      FutureOr<Response> m(EngineContext ctx, Next next) async => await next();
      expect(m, isA<Middleware>());
    });

    test('typed ContextKey read/write', () async {
      // RouteMetadata and ServiceResolver smoke tests
      final meta = RouteMetadata();
      const rk = RouteMetadataKey<String>('routed.test');
      meta.set(rk, 'hello');
      expect(meta.get(rk), 'hello');
      expect(meta.contains(rk), isTrue);
      meta.remove(rk);
      expect(meta.contains(rk), isFalse);

      final resolver = Container();
      expect(resolver, isA<ServiceResolver>());
      resolver.singleton<String>((_) async => 'hello');
      expect(resolver.has<String>(), isTrue);
      expect(await resolver.make<String>(), 'hello');
      // sync get after singleton cached? Need instance path via make then get
      // get requires instance binding - make caches instance for singleton
      expect(resolver.get<String>(), 'hello');
    });

    engineTest('TypedContextState write/read/require/contains', (engine, client) async {
      const userKey = ContextKey<String>('routed.test.user');
      const nullableKey = ContextKey<String?>('routed.test.nullable');
      const wrongKey = ContextKey<bool>('routed.test.user');

      final observed = <String, Object?>{}
        ..addAll({
          'absentContains': null,
          'absentRead': null,
          'absentRequire': null,
          'contains': null,
          'read': null,
          'require': null,
          'nullableContains': null,
          'nullableRead': null,
          'nullableRequire': null,
          'mismatchRead': null,
          'mismatchContains': null,
          'mismatchRequire': null,
        });
      engine.get('/typed-state', (ctx) {
        // Explicit extension invocation: the instance member write(String)
        // (response body writer) shadows the typed write otherwise.

        // Absent: contains false, read null, require throws.
        observed['absentContains'] = ctx.contains(userKey);
        observed['absentRead'] = ctx.read(userKey);
        try {
          ctx.require(userKey);
          observed['absentRequire'] = 'no-throw';
        } on StateError {
          observed['absentRequire'] = 'throws';
        }

        // Write + read + require + contains for a non-null value.
        TypedContextState(ctx).write(userKey, 'ada');
        observed['contains'] = ctx.contains(userKey);
        observed['read'] = ctx.read(userKey);
        observed['require'] = ctx.require(userKey);

        // A written null value (nullable T) is present and require returns null.
        TypedContextState(ctx).write(nullableKey, null);
        observed['nullableContains'] = ctx.contains(nullableKey);
        observed['nullableRead'] = ctx.read<String?>(nullableKey);
        observed['nullableRequire'] = ctx.require<String?>(nullableKey);

        // Legacy string set with a different type: read returns null (no cast throw).
        ctx.set('routed.test.user', 42);
        observed['mismatchRead'] = ctx.read<String>(userKey);
        // Presence is keyed by name only, so the key remains present.
        observed['mismatchContains'] = ctx.contains(wrongKey);
        // A present value of an incompatible type throws a StateError.
        try {
          ctx.require<bool>(wrongKey);
          observed['mismatchRequire'] = 'no-throw';
        } on StateError {
          observed['mismatchRequire'] = 'throws';
        }

        return ctx.string('ok');
      });

      final res = await client.get('/typed-state');
      res.assertStatus(200);
      expect(observed['absentContains'], isFalse);
      expect(observed['absentRead'], isNull);
      expect(observed['absentRequire'], 'throws');
      expect(observed['contains'], isTrue);
      expect(observed['read'], 'ada');
      expect(observed['require'], 'ada');
      expect(observed['nullableContains'], isTrue);
      expect(observed['nullableRead'], isNull);
      expect(observed['nullableRequire'], isNull);
      expect(observed['mismatchRead'], isNull);
      expect(observed['mismatchContains'], isTrue);
      expect(observed['mismatchRequire'], 'throws');
    });

    test('transport abstractions are importable and constructible', () {
      const opts = ServerOptions(host: '127.0.0.1', port: 8443, shared: true);
      expect(opts.host, '127.0.0.1');
      expect(opts.port, 8443);
      expect(opts.shared, isTrue);

      // Compile-time references for every exported transport contract.
      final RequestAdapter req = _FakeRequestAdapter();
      final ResponseAdapter res = _FakeResponseAdapter();
      final ServerHandle handle = _FakeServerHandle();
      final ServerTransport transport = _FakeServerTransport();
      expect(req, isA<RequestAdapter>());
      expect(res, isA<ResponseAdapter>());
      expect(handle, isA<ServerHandle>());
      expect(transport, isA<ServerTransport>());
      expect(handle.host, '127.0.0.1');
      expect(handle.port, 8443);
    });

    test('routed barrel does not re-export server_* packages', () {
      // when running from workspace root, path is packages/routed/lib/routed.dart
      final candidates = [
        File('lib/routed.dart'),
        File('packages/routed/lib/routed.dart'),
      ];
      File? barrel;
      for (final f in candidates) {
        if (f.existsSync()) barrel = f;
      }
      expect(barrel, isNotNull);
      final content = barrel!.readAsStringSync();
      expect(content.contains("package:server_"), isFalse);
    });
  });
}

class _FakeRequestAdapter implements RequestAdapter {
  @override
  String get method => 'GET';

  @override
  Uri get uri => Uri.parse('/');

  @override
  Map<String, List<String>> get headers => const {};

  @override
  Stream<List<int>> get body => const Stream<List<int>>.empty();

  @override
  String? get remoteAddress => null;
}

class _FakeResponseAdapter implements ResponseAdapter {
  @override
  int statusCode = 200;

  @override
  void setHeader(String name, String value) {}

  @override
  void addHeader(String name, String value) {}

  @override
  void write(List<int> bytes) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _FakeServerHandle implements ServerHandle {
  @override
  Future<void> close({bool force = false}) async {}

  @override
  String get host => '127.0.0.1';

  @override
  int get port => 8443;
}

class _FakeServerTransport implements ServerTransport {
  @override
  Future<ServerHandle> serve(Engine engine, ServerOptions options) async {
    return _FakeServerHandle();
  }
}
