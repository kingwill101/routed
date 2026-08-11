import 'package:routed/routed.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_sessions/server_sessions.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  late Engine engine;
  late MemorySessionStore store;
  late TestClient client;

  Future<void> setUpEngine() async {
    store = MemorySessionStore(
      codecs: [SecureCookie(useEncryption: false)],
      defaultOptions: SessionOptions(),
    );
    engine = Engine()..addGlobalMiddleware(sessionMiddleware(store));
    client = TestClient.inMemory(RoutedRequestHandler(engine));
  }

  // Routed's legacy in-tree session extension is still exported on this
  // branch (removed up-stack by the foundation slim), so use the explicit
  // extension override to disambiguate.
  Session sessionOf(EngineContext ctx) => SessionEngineContext(ctx).session;

  group('sessionMiddleware lifecycle', () {
    test('creates a session, exposes it under ctx, and persists a cookie',
        () async {
      await setUpEngine();
      engine.get('/check', (EngineContext ctx) async {
        if (!SessionEngineContext(ctx).hasSession) {
          ctx.status(400);
          ctx.string('no session');
          return;
        }
        final session = sessionOf(ctx);
        session.setValue(
          'visits',
          (session.getValue<int>('visits') ?? 0) + 1,
        );
        ctx.string('ok');
      });

      final response = await client.get('/check');
      response.assertStatus(200).assertBodyContains('ok');
      final setCookies = response.headers[HttpHeaders.setCookieHeader];
      expect(setCookies, isNotEmpty,
          reason: 'the store must write the session cookie');
      expect(response.cookie(defaultSessionName), isNotNull);
    });

    test('session value persists across requests via the cookie', () async {
      await setUpEngine();
      engine.get('/visit', (EngineContext ctx) async {
        final session = sessionOf(ctx);
        final visits = (session.getValue<int>('visits') ?? 0) + 1;
        session.setValue('visits', visits);
        ctx.string('visits=$visits');
      });

      final first = await client.get('/visit');
      first.assertStatus(200).assertBodyContains('visits=1');
      final setCookies = first.headers[HttpHeaders.setCookieHeader];
      expect(setCookies, isNotEmpty);
      final cookieValue = setCookies!.first.split(';').first;

      final second = await client.get(
        '/visit',
        headers: {
          HttpHeaders.cookieHeader: [cookieValue],
        },
      );
      second.assertStatus(200).assertBodyContains('visits=2');
    });

    test('destroyed session expires the cookie and does not persist',
        () async {
      await setUpEngine();
      engine.get('/logout', (EngineContext ctx) async {
        sessionOf(ctx).destroy();
        ctx.string('logged out');
      });

      final response = await client.get('/logout');
      response.assertStatus(200).assertBodyContains('logged out');
      final setCookies = response.headers[HttpHeaders.setCookieHeader];
      expect(setCookies, isNotEmpty,
          reason: 'destroy must write an expiring cookie');
      expect(setCookies!.first, contains('Max-Age=0'));
    });
  });
}