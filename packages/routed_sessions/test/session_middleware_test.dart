import 'dart:convert';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
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
  // `string` is exposed by both EngineContextHelpers and RoutedViewRender;
  // use the explicit extension override to disambiguate.
  void writeString(EngineContext ctx, String text) =>
      EngineContextHelpers(ctx).string(text);

  group('sessionMiddleware lifecycle', () {
    test(
      'session cookie defaults are secure with an explicit local opt-out',
      () {
        final secure = SessionConfig.cookie(
          appKey:
              'base64:${base64Encode(List<int>.generate(32, (i) => i + 1))}',
        );
        expect(secure.secure, isTrue);
        expect(secure.httpOnly, isTrue);
        expect(secure.sameSite, SameSite.lax);

        final local = SessionConfig.cookie(
          appKey:
              'base64:${base64Encode(List<int>.generate(32, (i) => i + 1))}',
          options: SessionOptions(
            secure: false,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        );
        expect(local.secure, isFalse);
        expect(local.httpOnly, isTrue);
        expect(local.sameSite, SameSite.lax);
      },
    );

    test(
      'default Routed session cookies use safe browser attributes',
      () async {
        final defaultEngine = Engine(
          providers: [...Engine.defaultProviders, RoutedSessionsProvider()],
        )..addGlobalMiddleware(sessionMiddleware());
        defaultEngine.get('/cookie', (ctx) => ctx.string('ok'));
        await defaultEngine.initialize();
        addTearDown(defaultEngine.close);

        final defaultClient = TestClient.inMemory(
          RoutedRequestHandler(defaultEngine),
        );
        addTearDown(defaultClient.close);

        final response = await defaultClient.get('/cookie');
        final cookie = response.cookie('routed_session');

        expect(cookie, isNotNull);
        expect(cookie!.secure, isTrue);
        expect(cookie.httpOnly, isTrue);
        expect(cookie.sameSite, SameSite.lax);
      },
    );

    test(
      'creates a session, exposes it under ctx, and persists a cookie',
      () async {
        await setUpEngine();
        engine.get('/check', (EngineContext ctx) async {
          if (!SessionEngineContext(ctx).hasSession) {
            ctx.status(400);
            writeString(ctx, 'no session');
            return;
          }
          final session = sessionOf(ctx);
          session.setValue(
            'visits',
            (session.getValue<int>('visits') ?? 0) + 1,
          );
          writeString(ctx, 'ok');
        });

        final response = await client.get('/check');
        response.assertStatus(200).assertBodyContains('ok');
        final setCookies = response.headers[HttpHeaders.setCookieHeader];
        expect(
          setCookies,
          isNotEmpty,
          reason: 'the store must write the session cookie',
        );
        expect(response.cookie('routed_session'), isNotNull);
      },
    );

    test('session value persists across requests via the cookie', () async {
      await setUpEngine();
      engine.get('/visit', (EngineContext ctx) async {
        final session = sessionOf(ctx);
        final visits = (session.getValue<int>('visits') ?? 0) + 1;
        session.setValue('visits', visits);
        writeString(ctx, 'visits=$visits');
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

    test('destroyed session expires the cookie and does not persist', () async {
      await setUpEngine();
      engine.get('/logout', (EngineContext ctx) async {
        sessionOf(ctx).destroy();
        writeString(ctx, 'logged out');
      });

      final response = await client.get('/logout');
      response.assertStatus(200).assertBodyContains('logged out');
      final setCookies = response.headers[HttpHeaders.setCookieHeader];
      expect(
        setCookies,
        isNotEmpty,
        reason: 'destroy must write an expiring cookie',
      );
      expect(setCookies!.first, contains('Max-Age=0'));
    });
  });
}
