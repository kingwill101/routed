// Smoke tests for PR #18 review fixes:
// 1. POSTed OAuth callbacks (Apple form_post) are accepted and form payload
//    fields (code/state) are merged into the callback decision.
// 2. AuthRoutes resolves the live manager via managerOf after reload.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart'
    hide
        AuthManager,
        AuthRoutes,
        AuthOptions,
        AuthUser,
        AuthSessionStrategy,
        AuthProvider,
        OAuthProvider,
        CredentialsProvider,
        SessionAuth,
        CallbackResult,
        CallbackProvider,
        AuthProviderType;
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_auth/server_auth.dart' as server_auth;

import '../test_engine.dart';

Engine _authEngine(AuthManager manager) {
  final sessionConfig = SessionConfig.cookie(
    appKey: 'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
    cookieName: 'test_session',
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

void main() {
  group('AuthRoutes POST callback (Apple form_post)', () {
    test('merges form body into custom callback params and proceeds', () async {
      Map<String, String>? receivedParams;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: [
            _CustomCallbackProvider(
              onCallback: (ctx, params) {
                receivedParams = params;
                return server_auth.CallbackResult.success(
                  server_auth.AuthUser(
                    id: 'custom-user',
                    email: params['email'],
                  ),
                );
              },
            ),
          ],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.post(
        '/auth/callback/custom',
        'code=form-code&state=form-state&email=user%40example.com',
        headers: {
          'Content-Type': ['application/x-www-form-urlencoded'],
        },
      );
      print('BODY1: ${response.body}');
      if (!(response.statusCode == HttpStatus.ok)) {
        fail('POST callback failed: ${response.statusCode} ${response.body}');
      }
      expect(receivedParams, isNotNull);
      expect(receivedParams!['code'], equals('form-code'));
      expect(receivedParams!['state'], equals('form-state'));
      expect(receivedParams!['email'], equals('user@example.com'));
      expect(response.json()['user']['email'], equals('user@example.com'));
    });

    test('GET callback passes query parameters to custom provider', () async {
      Map<String, String>? receivedParams;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: [
            _CustomCallbackProvider(
              onCallback: (ctx, params) {
                receivedParams = params;
                return server_auth.CallbackResult.success(
                  server_auth.AuthUser(
                    id: 'custom-user',
                    email: params['email'],
                  ),
                );
              },
            ),
          ],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.get(
        '/auth/callback/custom?code=code123&state=state123&email=get%40example.com',
      );
      print('BODY2: ${response.body}');
      if (!(response.statusCode == HttpStatus.ok)) {
        fail('GET callback failed: ${response.statusCode} ${response.body}');
      }
      expect(receivedParams!['code'], equals('code123'));
      expect(receivedParams!['email'], equals('get@example.com'));
    });
  });

  group('AuthRoutes manager binding', () {
    test(
      'managerOf getter is consulted so handlers track reloaded manager',
      () async {
        AuthManager? current;
        AuthManager newManager() => AuthManager(
          AuthOptions<EngineContext>(
            providers: [
              CredentialsProvider(
                authorize: (_, _, credentials) async {
                  final userId = credentials.email == 'new@example.com'
                      ? 'reloaded'
                      : 'initial';
                  return server_auth.AuthUser(
                    id: userId,
                    email: credentials.email,
                  );
                },
              ),
            ],
            enforceCsrf: false,
          ),
        );

        final initial = newManager();
        current = initial;
        final engine = testEngine(
          config: EngineConfig(
            security: const EngineSecurityFeatures(csrfProtection: false),
          ),
          options: [
            withSessionConfig(
              SessionConfig.cookie(
                appKey:
                    'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
                cookieName: 'test_session',
              ),
            ),
          ],
        );
        engine.addGlobalMiddleware(sessionMiddleware());
        AuthRoutes(
          initial,
          managerOf: () => current ?? initial,
        ).register(engine.defaultRouter);
        await engine.initialize();

        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        // Simulate a config reload replacing the manager instance.
        current = newManager();

        final response = await client.post(
          '/auth/signin/credentials',
          'email=new%40example.com&password=x',
          headers: {
            'Content-Type': ['application/x-www-form-urlencoded'],
          },
        );
        if (!(response.statusCode == HttpStatus.ok)) {
          fail('signin failed: ${response.statusCode} ${response.body}');
        }
        // The reloaded manager resolved the provider, proving managerOf won.
        expect(response.json()['user']['id'], equals('reloaded'));
      },
    );
  });
}

class _CustomCallbackProvider extends server_auth.AuthProvider
    with server_auth.CallbackProvider {
  _CustomCallbackProvider({required this.onCallback})
    : super(
        id: 'custom',
        name: 'Custom',
        type: server_auth.AuthProviderType.oauth,
      );

  final FutureOr<server_auth.CallbackResult> Function(
    server_auth.AuthContext ctx,
    Map<String, String> params,
  )
  onCallback;

  @override
  FutureOr<server_auth.CallbackResult> handleCallback(
    server_auth.AuthContext ctx,
    Map<String, String> params,
  ) {
    return onCallback(ctx, params);
  }
}
