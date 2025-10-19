import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

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

void main() {
  group('SessionAuthService', () {
    test(
      'remember-me login persists across requests and allows guards',
      () async {
        SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

        final engine = Engine(
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

      final engine = Engine(
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
  });
}
