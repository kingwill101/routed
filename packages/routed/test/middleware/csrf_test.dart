import 'dart:convert';
import 'dart:io';

import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('csrfMiddleware', () {
    SessionConfig buildSessionConfig() => SessionConfig(
      store: CookieStore(
        codecs: [
          SecureCookie(
            useEncryption: true,
            useSigning: true,
            key:
                'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
          ),
        ],
        defaultOptions: Options(
          path: '/',
          maxAge: const Duration(hours: 1).inSeconds,
          secure: false,
          httpOnly: true,
          sameSite: SameSite.lax,
          domain: null,
        ),
      ),
      cookieName: 'test_session',
    );

    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

        test(
          'issues token once and accepts header-based submissions',
          () async {
            final sessionConfig = buildSessionConfig();
            final engine = Engine(
              middlewares: [csrfMiddleware()],
              options: [withSessionConfig(sessionConfig)],
            )..get('/form', (ctx) => ctx.string('ok'));

            client = TestClient(RoutedRequestHandler(engine), mode: mode);

            final first = await client.get('/form');
            first.assertStatus(HttpStatus.ok);
            final csrfCookieName = engine.config.security.csrfCookieName;
            final csrf = first.cookie(csrfCookieName)!;
            final sessionCookieName = sessionConfig.cookieName;
            final session = first.cookie(sessionCookieName);
            final cookieParts = <String>["${csrf.name}=${csrf.value}"];
            if (session != null) {
              cookieParts.add("${session.name}=${session.value}");
            }
            final cookieHeader = cookieParts.join('; ');

            final second = await client.get(
              '/form',
              headers: {
                'Cookie': [cookieHeader],
              },
            );
            second.assertStatus(HttpStatus.ok);
            final updatedCookies = List<String>.from(
              second.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
            );
            final refreshedCsrf = updatedCookies.firstWhere(
              (String value) => value.startsWith('$csrfCookieName='),
              orElse: () => '',
            );
            if (refreshedCsrf.isNotEmpty) {
              final refreshedToken = refreshedCsrf
                  .split(';')
                  .first
                  .substring(refreshedCsrf.indexOf('=') + 1);
              expect(refreshedToken, isNotEmpty);
            }
          },
        );

        test('rejects POST without CSRF token', () async {
          final sessionConfig = buildSessionConfig();
          final engine = Engine(
            middlewares: [csrfMiddleware()],
            options: [withSessionConfig(sessionConfig)],
          )..post('/submit', (ctx) => ctx.string('submitted'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          final response = await client.post('/submit', 'data');
          response.assertStatus(HttpStatus.forbidden);
        });

        test('accepts POST with valid CSRF token in header', () async {
          final sessionConfig = buildSessionConfig();
          final engine =
              Engine(
                  middlewares: [csrfMiddleware()],
                  options: [withSessionConfig(sessionConfig)],
                )
                ..get('/form', (ctx) => ctx.string('form'))
                ..post('/submit', (ctx) => ctx.string('submitted'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // Get CSRF token
          final first = await client.get('/form');

          first.assertStatus(HttpStatus.ok);
          final csrfCookieName = engine.config.security.csrfCookieName;
          final csrf = first.cookie(csrfCookieName)!;
          final sessionCookieName = sessionConfig.cookieName;
          final session = first.cookie(sessionCookieName);

          final cookieParts = <String>["${csrf.name}=${csrf.value}"];
          if (session != null) {
            cookieParts.add("${session.name}=${session.value}");
          }

          // Submit with token and cookies
          final response = await client.post(
            '/submit',
            'data',
            headers: {
              'Cookie': [cookieParts.join('; ')],
              'X-CSRF-Token': [csrf.value],
            },
          );
          response.assertStatus(HttpStatus.ok);
        });

        test('token persists across multiple requests', () async {
          final sessionConfig = buildSessionConfig();
          final engine =
              Engine(
                  middlewares: [csrfMiddleware()],
                  options: [withSessionConfig(sessionConfig)],
                )
                ..get('/page1', (ctx) => ctx.string('page1'))
                ..get('/page2', (ctx) => ctx.string('page2'))
                ..get('/page3', (ctx) => ctx.string('page3'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // First request
          final first = await client.get('/page1');
          first.assertStatus(HttpStatus.ok);
          final headerValue1 = first.header(HttpHeaders.setCookieHeader);
          final cookies1 = headerValue1 is List
              ? List<String>.from(headerValue1)
              : <String>[headerValue1.toString()];
          final csrfCookieName = engine.config.security.csrfCookieName;
          final rawCsrfCookie1 = cookies1.firstWhere(
            (String value) => value.startsWith('$csrfCookieName='),
          );
          final csrfCookie1 = rawCsrfCookie1.split(',').first;
          final token1 = csrfCookie1
              .split(';')
              .first
              .substring(csrfCookie1.indexOf('=') + 1);

          // Second request with same token
          final second = await client.get(
            '/page2',
            headers: {
              'Cookie': ['$csrfCookieName=$token1'],
            },
          );
          second.assertStatus(HttpStatus.ok);

          // Third request with same token
          final third = await client.get(
            '/page3',
            headers: {
              'Cookie': ['$csrfCookieName=$token1'],
            },
          );
          third.assertStatus(HttpStatus.ok);
        });

        test('safe methods bypass CSRF check', () async {
          final sessionConfig = buildSessionConfig();
          final engine =
              Engine(
                  middlewares: [csrfMiddleware()],
                  options: [withSessionConfig(sessionConfig)],
                )
                ..get('/safe-get', (ctx) => ctx.string('ok'))
                ..head('/safe-head', (ctx) => ctx.string('ok'))
                ..options('/safe-options', (ctx) => ctx.string('ok'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // GET without token should work
          final getResponse = await client.get('/safe-get');
          getResponse.assertStatus(HttpStatus.ok);

          // HEAD without token should work
          final headResponse = await client.head('/safe-head');
          headResponse.assertStatus(HttpStatus.ok);

          // OPTIONS without token should work
          final optionsResponse = await client.options('/safe-options');
          optionsResponse.assertStatus(HttpStatus.ok);
        });
      });
    }
  });
}
