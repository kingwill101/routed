import 'dart:convert';

import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/sessions/cookie_store.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  void configureSessionRoutes(Engine engine) {
    engine.get('/session-test', (ctx) async {
      ctx.setSession('test', 'value');
      return ctx.string('ok');
    });

    engine.get('/write', (ctx) async {
      ctx.setSession('key', 'persisted');
      return ctx.string('written');
    });

    engine.get('/read', (ctx) async {
      final value = ctx.getSession<String>('key');
      return ctx.string(value ?? '');
    });

    engine.get('/create-session', (ctx) async {
      ctx.setSession('foo', 'bar');
      return ctx.string('ok');
    });

    engine.get('/initial', (ctx) async {
      ctx.setSession('foo', 'bar');
      ctx.setSession('count', '42');
      return ctx.string('ok');
    });

    engine.get('/verify', (ctx) async {
      assert(ctx.getSession<String>('foo') == "bar");
      assert(ctx.getSession<String>('count') == "42");
      return ctx.string('ok');
    });

    engine.get('/regenerate', (ctx) async {
      ctx.setSession('before', 'old');
      ctx.regenerateSession();
      ctx.setSession('after', 'new');
      return ctx.string('regenerated');
    });

    engine.get('/destroy', (ctx) async {
      ctx.setSession('data', 'secret');
      ctx.destroySession();
      return ctx.string('destroyed');
    });

    engine.get('/session-utils', (ctx) async {
      ctx.setSession('key1', 'value1');
      ctx.setSession('key2', 'value2');

      assert(ctx.hasSession('key1') == true);
      assert(ctx.hasSession('nonexistent') == false);

      assert(ctx.getSessionOrDefault('key1', 'default') == 'value1');
      assert(ctx.getSessionOrDefault('nonexistent', 'default') == 'default');

      ctx.removeSession('key1');
      assert(ctx.hasSession('key1') == false);

      expect(ctx.sessionData, containsPair('key2', 'value2'));

      ctx.clearSession();
      assert(ctx.sessionData.isEmpty);

      assert(ctx.sessionAge >= 0);
      assert(ctx.sessionIdleTime >= 0);
      assert(ctx.sessionId.isNotEmpty);
      return ctx.string('ok');
    });
  }

  void runSessionSuite(String description, TransportMode transportMode) {
    engineGroup(
      'Session operations ($description)',
      transportMode: transportMode,
      options: [
        withSessionConfig(
          SessionConfig(
            store: CookieStore(
              codecs: [
                SecureCookie(
                  useEncryption: true,
                  useSigning: true,
                  key:
                      'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
                ),
              ],
            ),
            cookieName: 'routed_session',
          ),
        ),
        configureSessionRoutes,
      ],
      define: (engine, client, tess) {
        tess('Engine has configured middleware', (
          Engine engine,
          TestClient client,
        ) async {
          expect(engine.middlewares, isNotEmpty);
        });

        tess('Session is available when configured in engine', (
          Engine engine,
          TestClient client,
        ) async {
          final response = await client.get('/session-test');
          response
            ..assertStatus(200)
            ..assertHasHeader(HttpHeaders.setCookieHeader)
            ..assertBodyEquals('ok');

          final setCookies =
              response.headers[HttpHeaders.setCookieHeader] ?? const [];
          expect(setCookies, isNotEmpty);
          expect(setCookies.any((c) => c.contains('routed_session=')), isTrue);
          // Session cookie should not leak raw values
          expect(setCookies.any((c) => c.contains('"test":"value"')), isFalse);
        });

        String? cookieVal(TestResponse res, String key) =>
            res.cookie(key)?.value;

        tess('Session persists between requests', (
          Engine engine,
          TestClient client,
        ) async {
          final writeResponse = await client.get('/write');
          final cookieHeader = cookieVal(
            writeResponse,
            engine.container.get<SessionConfig>().cookieName,
          );

          final cookieName = engine.container.get<SessionConfig>().cookieName;
          final readResponse = await client.get(
            '/read',
            headers: {
              if (cookieHeader != null)
                HttpHeaders.cookieHeader: ['$cookieName=$cookieHeader'],
            },
          );

          readResponse
            ..assertStatus(200)
            ..assertBodyEquals('persisted');
        });

        tess('Session creation and storage', (
          Engine engine,
          TestClient client,
        ) async {
          final response = await client.get('/create-session');
          response.assertStatus(200);

          final setCookies =
              response.headers[HttpHeaders.setCookieHeader] ?? const [];
          expect(setCookies, isNotEmpty);
          final cookieHeader = cookieVal(
            response,
            engine.container.get<SessionConfig>().cookieName,
          );
          expect(cookieHeader, isNotNull);
          expect(cookieHeader, isNotEmpty);
        });

        tess('Session loading from cookie', (
          Engine engine,
          TestClient client,
        ) async {
          final initialResponse = await client.get('/initial');
          final cookieHeader = cookieVal(
            initialResponse,
            engine.container.get<SessionConfig>().cookieName,
          );

          final cookieName = engine.container.get<SessionConfig>().cookieName;
          final verifyResponse = await client.get(
            '/verify',
            headers: {
              if (cookieHeader != null)
                HttpHeaders.cookieHeader: ['$cookieName=$cookieHeader'],
            },
          );
          verifyResponse.assertStatus(200);
        });

        tess('Session can be regenerated', (
          Engine engine,
          TestClient client,
        ) async {
          final response = await client.get('/regenerate');
          response.assertStatus(200);

          final cookieHeader = cookieVal(
            response,
            engine.container.get<SessionConfig>().cookieName,
          );
          expect(cookieHeader, isNotNull);
          expect(cookieHeader, isNotEmpty);
        });

        tess('Session can be destroyed', (
          Engine engine,
          TestClient client,
        ) async {
          final response = await client.get('/destroy');
          response.assertStatus(200);

          final setCookies =
              response.headers[HttpHeaders.setCookieHeader] ?? const [];
          expect(
            setCookies.any((value) => value.contains('Max-Age=0')),
            isTrue,
          );
        });

        tess('Session utility methods work correctly', (
          Engine engine,
          TestClient client,
        ) async {
          final response = await client.get('/session-utils');
          response.assertStatus(200);
        });
      },
    );
  }

  runSessionSuite('in-memory transport', TransportMode.inMemory);
  runSessionSuite('ephemeral transport', TransportMode.ephemeralServer);

  test('read-only sessions avoid emitting Set-Cookie headers', () async {
    const cookieName = 'routed_session';
    final generator = Gen.integer(min: 0, max: 4);
    final runner = PropertyTestRunner<int>(generator, (reads) async {
      final sessionConfig = SessionConfig(
        cookieName: cookieName,
        store: CookieStore(
          codecs: [
            SecureCookie(
              useEncryption: true,
              useSigning: true,
              key: SecureCookie.generateKey(),
            ),
          ],
        ),
      );

      final engine = testEngine(options: [withSessionConfig(sessionConfig)])
        ..get('/login', (ctx) {
          ctx.setSession('user', 'alice');
          return ctx.string('ok');
        })
        ..get('/profile', (ctx) {
          ctx.getSession<String>('user');
          return ctx.string('profile');
        });

      final client = TestClient(RoutedRequestHandler(engine));
      final loginResponse = await client.get('/login');
      final cookie = loginResponse.cookie(cookieName);
      expect(cookie, isNotNull);
      final cookieHeader = '${cookie!.name}=${cookie.value}';

      for (var i = 0; i < reads; i++) {
        final response = await client.get(
          '/profile',
          headers: {
            HttpHeaders.cookieHeader: [cookieHeader],
          },
        );

        response.assertStatus(200);
        final List<String>? setCookieHeader =
            response.headers[HttpHeaders.setCookieHeader];
        if (setCookieHeader == null || setCookieHeader.isEmpty) {
          continue;
        }
        fail('Unexpected Set-Cookie header(s): $setCookieHeader');
      }

      await client.close();
    }, PropertyConfig(numTests: 25, seed: 20250229));

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
