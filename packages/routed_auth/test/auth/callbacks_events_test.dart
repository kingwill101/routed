import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

Engine _authEngine(AuthManager manager) {
  final sessionConfig = _sessionConfig();
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [RoutedSessionsProvider(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

final class _LifecycleRecordingPlugin
    implements
        AuthServerPlugin<EngineContext>,
        AuthAuthenticationLifecycleContributor<EngineContext> {
  final events = <AuthAuthenticationLifecycleEventType>[];

  @override
  String get id => 'lifecycle_recording';

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  @override
  void configure(AuthServerPluginContext<EngineContext> context) {}

  @override
  Future<void> onAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<EngineContext> event,
  ) async {
    events.add(event.type);
  }
}

void main() {
  group('Auth callbacks and events', () {
    test('signIn callback can deny sign-in', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
          callbacks: const AuthCallbacks(signIn: _denySignIn),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.unauthorized);
      expect(signInResponse.json()['error'], equals('sign_in_blocked'));
    });

    test('session callback decorates payload', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
          callbacks: AuthCallbacks(
            session: (context) async {
              return {...context.payload, 'note': 'custom'};
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      expect(signInResponse.json()['note'], equals('custom'));

      final authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);

      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      expect(sessionResponse.json()['note'], equals('custom'));
    });

    test('jwt callback augments claims', () async {
      const jwtSecret = 'jwt-secret';
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: jwtSecret),
          enforceCsrf: false,
          callbacks: AuthCallbacks(
            jwt: (context) async {
              return {...context.token, 'custom': 'value'};
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);

      final jwtCookie = signInResponse.cookie(
        manager.options.jwtOptions.cookieName,
      );
      expect(jwtCookie, isNotNull);

      final verifier = JwtVerifier(
        options: manager.options.jwtOptions.toVerifierOptions(),
      );
      final payload = await verifier.verifyToken(jwtCookie!.value);
      expect(payload.claims['custom'], equals('value'));
    });

    test('events fire on sign-in and sign-out', () async {
      final events = <String>[];
      final lifecyclePlugin = _LifecycleRecordingPlugin();
      AuthSignInEvent? signInEvent;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          plugins: [lifecyclePlugin],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final eventManager = await engine.container.make<EventManager>();
      eventManager.listen<AuthSignInEvent>((event) {
        signInEvent = event;
        events.add('sign_in:${event.user.id}');
      });
      eventManager.listen<AuthSignOutEvent>(
        (event) => events.add('sign_out:${event.user?.id}'),
      );
      eventManager.listen<AuthSessionEvent>((event) => events.add('session'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      expect(signInEvent?.credentials?.password, isNull);

      final authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);

      final signOutResponse = await client.postJson(
        '/auth/signout',
        {'_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      signOutResponse.assertStatus(HttpStatus.ok);

      expect(events, contains('sign_in:user-1'));
      expect(events, contains('sign_out:user-1'));
      expect(events, contains('session'));
      expect(
        lifecyclePlugin.events,
        contains(AuthAuthenticationLifecycleEventType.signedOut),
      );
    });

    test('account-link events identify the OAuth provider', () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'test-oauth',
        name: 'Test OAuth',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://oauth.test/authorize'),
        tokenEndpoint: Uri.parse('https://oauth.test/token'),
        userInfoEndpoint: Uri.parse('https://oauth.test/user'),
        redirectUri: 'https://app.test/auth/callback/test-oauth',
        usePkce: false,
        profile: (profile) => AuthUser(
          id: profile['sub']?.toString() ?? '',
          email: profile['email']?.toString(),
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [provider],
          enforceCsrf: false,
          httpClient: MockClient((request) async {
            if (request.url.path == '/token') {
              return http.Response(
                jsonEncode({'access_token': 'access-token'}),
                HttpStatus.ok,
              );
            }
            expect(request.url.path, '/user');
            return http.Response(
              jsonEncode({'sub': 'oauth-user', 'email': 'oauth@example.com'}),
              HttpStatus.ok,
            );
          }),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      AuthLinkAccountEvent? linked;
      final eventManager = await engine.container.make<EventManager>();
      eventManager.listen<AuthLinkAccountEvent>((event) => linked = event);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      final csrfResponse = await client.get('/auth/csrf');
      final initialCookie = csrfResponse.cookie('test_session')!;
      final started = await client.get(
        '/auth/signin/test-oauth',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
        },
      );
      started.assertStatus(HttpStatus.found);
      final state = Uri.parse(
        started.headers[HttpHeaders.locationHeader]!.single,
      ).queryParameters['state']!;
      final callbackCookie = started.cookie('test_session') ?? initialCookie;

      final completed = await client.get(
        '/auth/callback/test-oauth?code=code&state=$state',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(callbackCookie)],
        },
      );

      completed.assertStatus(HttpStatus.ok);
      expect(linked?.provider?.id, 'test-oauth');
    });

    test('event projections do not retain auth secrets', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      engine.defaultRouter.get('/event-probe', (ctx) {
        final provider = OAuthProvider<Map<String, dynamic>>(
          id: 'oauth',
          name: 'OAuth',
          clientId: 'client-id',
          clientSecret: 'client-secret',
          authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
          tokenEndpoint: Uri.parse('https://auth.test/token'),
          redirectUri: 'https://app.test/auth/callback/oauth',
          profile: (_) => AuthUser(id: 'user-1'),
        );
        final account = AuthAccount(
          providerId: 'oauth',
          providerAccountId: 'account-1',
          accessToken: 'access-secret',
          refreshToken: 'refresh-secret',
          metadata: {
            'nested': {'client_secret': 'nested-secret'},
          },
        );
        final session = AuthSession(
          user: AuthUser(
            id: 'user-1',
            attributes: {
              'nested': {'token': 'nested-secret'},
            },
          ),
          expiresAt: DateTime.utc(2030),
          strategy: AuthSessionStrategy.jwt,
          token: 'jwt-secret',
        );
        final signIn = AuthSignInEvent(
          context: ctx,
          user: session.user,
          session: session,
          strategy: AuthSessionStrategy.jwt,
          provider: provider,
          account: account,
          profile: {
            'name': 'Alice',
            'nested': {'access_token': 'profile-secret'},
          },
          credentials: AuthCredentials(
            password: 'password-secret',
            attributes: {
              'nested': {'password': 'nested-secret'},
            },
          ),
        );
        final sessionEvent = AuthSessionEvent(
          context: ctx,
          session: session,
          strategy: AuthSessionStrategy.jwt,
          provider: provider,
          payload: {'token': 'payload-secret', 'visible': true},
        );

        expect(signIn.provider, isNot(same(provider)));
        expect(signIn.provider, isNot(isA<OAuthProvider>()));
        expect(signIn.account!.accessToken, isNull);
        expect(signIn.account!.refreshToken, isNull);
        expect(signIn.session.token, isNull);
        expect(signIn.user.attributes, equals({'nested': {}}));
        expect(signIn.profile, equals({'name': 'Alice', 'nested': {}}));
        expect(signIn.credentials!.password, isNull);
        expect(signIn.credentials!.attributes, equals({'nested': {}}));
        expect(sessionEvent.session.token, isNull);
        expect(sessionEvent.payload, equals({'visible': true}));

        return ctx.json({'ok': true});
      });
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());
      final response = await client.get('/event-probe');

      response.assertStatus(HttpStatus.ok);
    });

    test('redirect callback receives request baseUrl', () async {
      String? observedBaseUrl;

      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
          callbacks: AuthCallbacks(
            signIn: (context) =>
                const AuthSignInResult.allow(redirectUrl: '/from-signin'),
            redirect: (context) {
              observedBaseUrl = context.baseUrl;
              return '/after-signin';
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );

      signInResponse.assertStatus(HttpStatus.movedTemporarily);
      final location = signInResponse.headers[HttpHeaders.locationHeader];
      expect(location, isNotNull);
      expect(location!.first, equals('/after-signin'));
      expect(observedBaseUrl, equals('http://server_testing.internal'));
    });
  });
}

AuthSignInResult _denySignIn(AuthSignInCallbackContext<EngineContext> context) {
  return const AuthSignInResult.deny();
}
