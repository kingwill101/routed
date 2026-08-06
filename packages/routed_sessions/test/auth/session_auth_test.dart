import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: Options(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

class TrackingRememberStore implements RememberTokenStore {
  final Map<String, AuthPrincipal> saved = <String, AuthPrincipal>{};
  final Map<String, DateTime> expirations = <String, DateTime>{};
  final List<String> removed = <String>[];
  int saveCount = 0;
  String? lastToken;

  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) async {
    saveCount += 1;
    saved[token] = principal;
    expirations[token] = expiresAt;
    lastToken = token;
  }

  @override
  Future<AuthPrincipal?> read(String token) async {
    final expiry = expirations[token];
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      await remove(token);
      return null;
    }
    return saved[token];
  }

  @override
  Future<void> remove(String token) async {
    removed.add(token);
    saved.remove(token);
    expirations.remove(token);
  }
}

class MissingRememberStore implements RememberTokenStore {
  final List<String> removed = <String>[];

  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) async {}

  @override
  Future<AuthPrincipal?> read(String token) async => null;

  @override
  Future<void> remove(String token) async {
    removed.add(token);
  }
}

void main() {
  group('SessionAuthService', () {
    test(
      'remember-me login persists across requests and allows guards',
      () async {
        SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

        final engine = testEngine(
          config: EngineConfig(
            security: const EngineSecurityFeatures(csrfProtection: false),
          ),
          options: [withSessionConfig(_sessionConfig())],
        );

        engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

        engine.post('/login', (ctx) async {
          final principal = AuthPrincipal(id: 'user-1', roles: const ['admin']);
          await SessionAuth.login(
            ctx,
            principal,
            rememberMe: true,
            rememberDuration: const Duration(days: 7),
          );
          return ctx.json({'status': 'ok'});
        });

        engine.get('/me', (ctx) {
          final principal = SessionAuth.current(ctx);
          return ctx.json({'id': principal?.id, 'roles': principal?.roles});
        });

        GuardRegistry.instance.register('admin-only', requireRoles(['admin']));

        engine.get(
          '/admin',
          (ctx) => ctx.string('secure'),
          middlewares: [
            guardMiddleware(['authenticated', 'admin-only']),
          ],
        );

        await engine.initialize();

        final client = TestClient(
          RoutedRequestHandler(engine),
          mode: TransportMode.ephemeralServer,
        );
        addTearDown(() async => await client.close());
        addTearDown(() {
          GuardRegistry.instance.unregister('admin-only');
        });

        final loginResponse = await client.post('/login', '');
        loginResponse.assertStatus(200);
        final rememberCookie = loginResponse.cookie('remember_token');
        expect(rememberCookie, isNotNull);

        final meResponse = await client.get(
          '/me',
          headers: {
            HttpHeaders.cookieHeader: [
              'remember_token=${rememberCookie!.value}',
            ],
          },
        );
        meResponse.assertStatus(200);
        expect(meResponse.json()['id'], equals('user-1'));
        expect(meResponse.json()['roles'], contains('admin'));
        final rotatedCookie = meResponse.cookie('remember_token');
        expect(rotatedCookie, isNotNull);
        expect(rotatedCookie!.value, isNot(equals(rememberCookie.value)));

        final adminResponse = await client.get(
          '/admin',
          headers: {
            HttpHeaders.cookieHeader: ['remember_token=${rotatedCookie.value}'],
          },
        );
        adminResponse.assertStatus(200);
        expect(adminResponse.body, equals('secure'));
      },
    );

    test('guard middleware denies principals missing required roles', () async {
      SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        options: [withSessionConfig(_sessionConfig())],
      );

      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

      GuardRegistry.instance.register('admin-only', requireRoles(['admin']));

      engine.post('/login-user', (ctx) async {
        final principal = AuthPrincipal(id: 'user-2', roles: const ['user']);
        await SessionAuth.login(ctx, principal, rememberMe: true);
        return ctx.json({'status': 'ok'});
      });

      engine.get(
        '/admin',
        (ctx) => ctx.string('secure'),
        middlewares: [
          guardMiddleware(['authenticated', 'admin-only']),
        ],
      );

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());
      addTearDown(() {
        GuardRegistry.instance.unregister('admin-only');
      });

      final loginResponse = await client.post('/login-user', '');
      loginResponse.assertStatus(200);
      final rememberCookie = loginResponse.cookie('remember_token');
      expect(rememberCookie, isNotNull);

      final forbidden = await client.get(
        '/admin',
        headers: {
          HttpHeaders.cookieHeader: ['remember_token=${rememberCookie!.value}'],
        },
      );
      expect(forbidden.statusCode, equals(HttpStatus.forbidden));
      expect(forbidden.body, contains('Forbidden'));
    });

    test('logout clears remember token and invalidates principal', () async {
      final store = TrackingRememberStore();
      SessionAuth.configure(rememberStore: store);

      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        options: [withSessionConfig(_sessionConfig())],
      );

      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

      engine.post('/login', (ctx) async {
        final principal = AuthPrincipal(id: 'user-logout', roles: const []);
        SessionAuth.configure(rememberStore: store);
        await SessionAuth.login(ctx, principal, rememberMe: true);
        return ctx.json({'status': 'ok'});
      });

      engine.post('/logout', (ctx) async {
        await SessionAuth.logout(ctx);
        return ctx.json({'status': 'logged-out'});
      });

      engine.get('/me', (ctx) {
        final principal = SessionAuth.current(ctx);
        if (principal == null) {
          ctx.response
            ..statusCode = HttpStatus.unauthorized
            ..write('not signed in');
          return ctx.response;
        }
        return ctx.json({'id': principal.id});
      });

      await engine.initialize();
      addTearDown(() async => await engine.close());

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final loginResponse = await client.post('/login', '');
      loginResponse.assertStatus(200);
      final rememberCookie = loginResponse.cookie('remember_token');
      expect(rememberCookie, isNotNull);
      expect(store.saveCount, equals(1));
      expect(store.lastToken, equals(rememberCookie!.value));
      final sessionCookie = loginResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);
      expect(store.saved.containsKey(rememberCookie.value), isTrue);

      final meResponseBefore = await client.get(
        '/me',
        headers: {
          HttpHeaders.cookieHeader: [
            'test_session=${sessionCookie!.value}; remember_token=${rememberCookie.value}',
          ],
        },
      );
      meResponseBefore.assertStatus(200);

      final logoutResponse = await client.post(
        '/logout',
        '',
        headers: {
          HttpHeaders.cookieHeader: [
            'test_session=${sessionCookie.value}; remember_token=${rememberCookie.value}',
          ],
        },
      );
      logoutResponse.assertStatus(200);
      expect(store.saved.containsKey(rememberCookie.value), isFalse);
      expect(store.removed, contains(rememberCookie.value));

      final setCookies =
          logoutResponse.headers[HttpHeaders.setCookieHeader] ?? const [];
      expect(
        setCookies.any((value) => value.contains('remember_token=')),
        isTrue,
      );
      expect(
        setCookies.any(
          (value) =>
              value.contains('remember_token=;') &&
              (value.contains('Max-Age=0') || value.contains('max-age=0')),
        ),
        isTrue,
      );

      final meResponseAfter = await client.get(
        '/me',
        headers: {
          HttpHeaders.cookieHeader: ['remember_token=${rememberCookie.value}'],
        },
      );
      expect(meResponseAfter.statusCode, equals(HttpStatus.unauthorized));
      expect(meResponseAfter.body, contains('not signed in'));
    });

    test(
      'middleware clears unknown remember tokens and challenges client',
      () async {
        final store = MissingRememberStore();
        SessionAuth.configure(rememberStore: store);

        final engine = testEngine(
          config: EngineConfig(
            security: const EngineSecurityFeatures(csrfProtection: false),
          ),
          options: [withSessionConfig(_sessionConfig())],
        );

        engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

        GuardRegistry.instance.register(
          'auth-required',
          requireAuthenticated(),
        );
        engine.get(
          '/secure',
          (ctx) => ctx.string('ok'),
          middlewares: [
            guardMiddleware(['auth-required']),
          ],
        );

        await engine.initialize();
        addTearDown(() async => await engine.close());

        final client = TestClient(
          RoutedRequestHandler(engine),
          mode: TransportMode.ephemeralServer,
        );
        addTearDown(() async => await client.close());
        addTearDown(() {
          GuardRegistry.instance.unregister('auth-required');
        });

        final response = await client.get(
          '/secure',
          headers: {
            HttpHeaders.cookieHeader: ['remember_token=stale-token'],
          },
        );

        expect(response.statusCode, equals(HttpStatus.unauthorized));
        final header =
            response.headers[HttpHeaders.wwwAuthenticateHeader]?.first;
        expect(header, contains('Bearer realm="Restricted"'));
        final clearedCookie = response.cookie('remember_token');
        expect(clearedCookie, isNotNull);
        expect(clearedCookie!.value, isEmpty);
        expect(clearedCookie.maxAge, equals(0));
        expect(store.removed, contains('stale-token'));
      },
    );

    test('roles guard respects any/all matching', () async {
      final store = TrackingRememberStore();
      SessionAuth.configure(rememberStore: store);

      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        options: [withSessionConfig(_sessionConfig())],
      );

      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

      GuardRegistry.instance
        ..register('auth-only-test', requireAuthenticated())
        ..register(
          'support-any-test',
          requireRoles(['support', 'editor'], any: true),
        )
        ..register(
          'support-all-test',
          requireRoles(['support', 'editor'], any: false),
        );

      engine.post('/login', (ctx) async {
        final principal = AuthPrincipal(id: 'helper', roles: const ['support']);
        SessionAuth.configure(rememberStore: store);
        await SessionAuth.login(ctx, principal, rememberMe: true);
        return ctx.json({'status': 'ok'});
      });

      engine.get(
        '/support-any',
        (ctx) => ctx.string('allowed'),
        middlewares: [
          guardMiddleware(['auth-only-test', 'support-any-test']),
        ],
      );

      engine.get(
        '/support-all',
        (ctx) => ctx.string('allowed'),
        middlewares: [
          guardMiddleware(['auth-only-test', 'support-all-test']),
        ],
      );

      await engine.initialize();
      addTearDown(() async => await engine.close());
      addTearDown(() {
        GuardRegistry.instance
          ..unregister('auth-only-test')
          ..unregister('support-any-test')
          ..unregister('support-all-test');
      });

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final loginResponse = await client.post('/login', '');
      loginResponse.assertStatus(200);
      final rememberCookie = loginResponse.cookie('remember_token');
      expect(rememberCookie, isNotNull);

      final supportAny = await client.get(
        '/support-any',
        headers: {
          HttpHeaders.cookieHeader: ['remember_token=${rememberCookie!.value}'],
        },
      );
      supportAny.assertStatus(200);
      expect(supportAny.body, equals('allowed'));

      var activeToken = rememberCookie.value;
      final rotated = supportAny.cookie('remember_token');
      if (rotated != null && rotated.value.isNotEmpty) {
        activeToken = rotated.value;
      }

      final supportAll = await client.get(
        '/support-all',
        headers: {
          HttpHeaders.cookieHeader: ['remember_token=$activeToken'],
        },
      );
      expect(supportAll.statusCode, equals(HttpStatus.forbidden));
      expect(supportAll.body, contains('Forbidden by guard: support-all-test'));
    });

    test('guard can short-circuit with custom response', () async {
      SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        options: [withSessionConfig(_sessionConfig())],
      );

      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

      GuardRegistry.instance.register('maintenance-test', (ctx) {
        final response = ctx.string(
          'maintenance mode',
          statusCode: HttpStatus.serviceUnavailable,
        );
        return GuardResult.deny(response);
      });

      engine.get(
        '/feature',
        (ctx) => ctx.string('ok'),
        middlewares: [
          guardMiddleware(['maintenance-test']),
        ],
      );

      await engine.initialize();
      addTearDown(() async => await engine.close());
      addTearDown(() {
        GuardRegistry.instance.unregister('maintenance-test');
      });

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final response = await client.get('/feature');

      expect(response.statusCode, equals(HttpStatus.serviceUnavailable));
      expect(response.body, equals('maintenance mode'));
    });
  });
}
