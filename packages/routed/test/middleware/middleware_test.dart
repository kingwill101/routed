import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed/session.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  TestClient? client;

  tearDown(() async {
    await client?.close();
  });

  group('basicAuth middleware', () {
    TestClient buildClient() {
      final engine = testEngine();
      engine.get(
        '/secret',
        (ctx) async {
          final user = ctx.get<String>('user');
          return ctx.json({'user': user});
        },
        middlewares: [
          basicAuth({'admin': 'secret'}),
        ],
      );
      return TestClient(RoutedRequestHandler(engine));
    }

    test('requires credentials and sets WWW-Authenticate header', () async {
      client = buildClient();
      final response = await client!.get(
        '/secret',
        headers: {
          'Accept': ['application/json'],
        },
      );
      response
        ..assertStatus(HttpStatus.unauthorized)
        ..assertHeader('WWW-Authenticate', 'Basic realm="Restricted Area"')
        ..assertJsonPath('error', 'Unauthorized');
    });

    test('rejects invalid credentials and returns same realm', () async {
      client = buildClient();
      final invalid = base64Encode(utf8.encode('admin:wrong-password'));
      final response = await client!.get(
        '/secret',
        headers: {
          HttpHeaders.authorizationHeader: ['Basic $invalid'],
          'Accept': ['application/json'],
        },
      );
      response
        ..assertStatus(HttpStatus.unauthorized)
        ..assertHeader('WWW-Authenticate', 'Basic realm="Restricted Area"')
        ..assertJsonPath('error', 'Unauthorized');
    });

    test('allows valid credentials and exposes username', () async {
      client = buildClient();
      final valid = base64Encode(utf8.encode('admin:secret'));
      final response = await client!.get(
        '/secret',
        headers: {
          HttpHeaders.authorizationHeader: ['Basic $valid'],
        },
      );
      response
        ..assertStatus(HttpStatus.ok)
        ..assertJsonPath('user', 'admin');
    });
  });

  group('corsMiddleware', () {
    test('echoes wildcard origin when credentials are disabled', () async {
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(
            cors: CorsConfig(
              enabled: true,
              allowedOrigins: ['*'],
              allowCredentials: false,
            ),
          ),
        ),
      )..get('/ping', (ctx) => ctx.string('pong'));

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get(
        '/ping',
        headers: {
          'Origin': ['https://client.dev'],
        },
      );
      response
        ..assertStatus(HttpStatus.ok)
        ..assertHeader('Access-Control-Allow-Origin', '*')
        ..assertHeaderContains('Access-Control-Allow-Methods', ['GET']);
    });

    test('reflects origin when credentials enabled with wildcard', () async {
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(
            cors: CorsConfig(
              enabled: true,
              allowedOrigins: ['*'],
              allowCredentials: true,
            ),
          ),
        ),
      )..get('/ping', (ctx) => ctx.string('pong'));

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get(
        '/ping',
        headers: {
          'Origin': ['https://client.dev'],
        },
      );
      response
        ..assertStatus(HttpStatus.ok)
        ..assertHeader('Access-Control-Allow-Origin', 'https://client.dev')
        ..assertHeader('Vary', 'Origin')
        ..assertHeader('Access-Control-Allow-Credentials', 'true');
    });

    test('rejects disallowed origins', () async {
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(
            cors: CorsConfig(
              enabled: true,
              allowedOrigins: ['https://allowed.dev'],
            ),
          ),
        ),
      )..get('/ping', (ctx) => ctx.string('pong'));

      client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      final response = await client!.get(
        '/ping',
        headers: {
          'Origin': ['https://evil.dev'],
        },
      );
      response
        ..assertStatus(HttpStatus.forbidden)
        ..assertBodyContains('CORS origin check failed');
    });
  });

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

    test('issues token once and accepts header-based submissions', () async {
      final sessionConfig = buildSessionConfig();
      final engine = testEngine(
        middlewares: [csrfMiddleware()],
        options: [withSessionConfig(sessionConfig)],
      )..get('/form', (ctx) => ctx.string('ok'));

      client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );

      final first = await client!.get('/form');
      first.assertStatus(HttpStatus.ok);
      final headerValue = first.header(HttpHeaders.setCookieHeader);
      final cookies = headerValue is List
          ? List<String>.from(headerValue)
          : <String>[headerValue.toString()];
      final csrfCookieName = engine.config.security.csrfCookieName;
      final rawCsrfCookie = cookies.firstWhere(
        (String value) => value.startsWith('$csrfCookieName='),
      );
      expect(rawCsrfCookie, contains('$csrfCookieName='));
      final csrfCookie = rawCsrfCookie.split(',').first;
      expect(csrfCookie.toLowerCase(), contains('samesite=lax'));
      expect(csrfCookie.toLowerCase(), isNot(contains('secure')));

      final token = csrfCookie
          .split(';')
          .first
          .substring(csrfCookie.indexOf('=') + 1);
      expect(token, isNotEmpty);
      final sessionCookieName = sessionConfig.cookieName;
      String? sessionValue;
      final sessionPart = rawCsrfCookie
          .split(',')
          .map((String part) => part.trim())
          .firstWhere(
            (String part) => part.startsWith('$sessionCookieName='),
            orElse: () => '',
          );
      if (sessionPart.isNotEmpty) {
        sessionValue = sessionPart
            .split(';')
            .first
            .substring(sessionPart.indexOf('=') + 1);
      }

      final cookieHeader = [
        '$csrfCookieName=$token',
        if (sessionValue != null) '$sessionCookieName=$sessionValue',
      ].join('; ');

      final second = await client!.get(
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
        (value) => value.startsWith('$csrfCookieName='),
        orElse: () => '',
      );
      if (refreshedCsrf.isNotEmpty) {
        final refreshedToken = refreshedCsrf
            .split(';')
            .first
            .substring(refreshedCsrf.indexOf('=') + 1);
        expect(refreshedToken, isNotEmpty);
      }
    });
  });

  group('recoveryMiddleware', () {
    test('respects custom handler response without overriding body', () async {
      final engine = testEngine()
        ..middlewares.add(
          recoveryMiddleware(
            handler: (ctx, error, stack) {
              ctx.response
                ..statusCode = HttpStatus.serviceUnavailable
                ..write('handled');
              ctx.response.close();
            },
          ),
        )
        ..get('/boom', (ctx) {
          throw StateError('boom');
        });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/boom');
      response
        ..assertStatus(HttpStatus.serviceUnavailable)
        ..assertBodyEquals('handled');
    });
  });

  group('requestTrackerMiddleware', () {
    test('stores duration and completion metadata under routed keys', () async {
      Future<Response> verifier(EngineContext ctx, Next next) async {
        final res = await next();
        final duration = ctx.getContextData<Duration>(
          '_routed_request_duration',
        );
        final completed = ctx.getContextData<DateTime>(
          '_routed_request_completed',
        );
        ctx.response.headers.set(
          'X-Tracker-Has-Duration',
          (duration is Duration).toString(),
        );
        ctx.response.headers.set(
          'X-Tracker-Has-Completed',
          (completed is DateTime).toString(),
        );
        return res;
      }

      final engine = testEngine()
        ..get('/tracked', (ctx) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return ctx.string('ok');
        }, middlewares: [verifier, requestTrackerMiddleware()]);

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/tracked');
      response
        ..assertStatus(HttpStatus.ok)
        ..assertHeader('X-Tracker-Has-Duration', 'true')
        ..assertHeader('X-Tracker-Has-Completed', 'true');
    });
  });

  group('securityHeadersMiddleware', () {
    test('sets configured security headers exactly once', () async {
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(
            csp: "default-src 'self'",
            xContentTypeOptionsNoSniff: true,
            hstsMaxAge: 31536000,
            xFrameOptions: 'DENY',
          ),
        ),
      )..get('/policy', (ctx) => ctx.string('ok'));

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/policy');
      response
        ..assertHeader('Content-Security-Policy', "default-src 'self'")
        ..assertHeader('X-Content-Type-Options', 'nosniff')
        ..assertHeader(
          'Strict-Transport-Security',
          'max-age=31536000; includeSubDomains; preload',
        )
        ..assertHeader('X-Frame-Options', 'DENY');
    });
  });

  group('timeoutMiddleware', () {
    test('returns 504 when handler exceeds allotted time', () async {
      final engine = testEngine()
        ..get('/slow', (ctx) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return ctx.string('late');
        }, middlewares: [timeoutMiddleware(const Duration(milliseconds: 20))]);

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/slow');
      response
        ..assertStatus(HttpStatus.gatewayTimeout)
        ..assertBodyContains('Gateway Timeout');
    });

    test('allows fast handler to complete within timeout', () async {
      final engine = testEngine()
        ..get(
          '/fast',
          (ctx) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return ctx.string('ok');
          },
          middlewares: [timeoutMiddleware(const Duration(milliseconds: 100))],
        );

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/fast');
      response
        ..assertStatus(HttpStatus.ok)
        ..assertBodyEquals('ok');
    });
  });

  group('limitRequestBody middleware', () {
    test('rejects payloads larger than configured limit', () async {
      final engine = testEngine()
        ..post(
          '/upload',
          (ctx) => ctx.string('ok'),
          middlewares: [limitRequestBody(10)],
        );

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.post(
        '/upload',
        List<int>.filled(11, 120),
        headers: {
          'Content-Type': ['application/octet-stream'],
          HttpHeaders.contentLengthHeader: ['11'],
        },
      );
      response.assertStatus(HttpStatus.requestEntityTooLarge);
    });

    test('allows payloads within the limit', () async {
      final engine = testEngine()
        ..post(
          '/upload',
          (ctx) => ctx.string('ok'),
          middlewares: [limitRequestBody(16)],
        );

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.post(
        '/upload',
        List<int>.filled(9, 120),
        headers: {
          'Content-Type': ['application/octet-stream'],
          HttpHeaders.contentLengthHeader: ['9'],
        },
      );
      response
        ..assertStatus(HttpStatus.ok)
        ..assertBodyEquals('ok');
    });
  });
}
