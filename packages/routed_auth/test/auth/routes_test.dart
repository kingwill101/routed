import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_auth/server_auth.dart' as server_auth;
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

Map<String, dynamic>? _decodeJson(TestResponse response) {
  final body = response.body.trim();
  if (body.isEmpty) {
    return null;
  }
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return null;
}

void main() {
  group('AuthRoutes', () {
    test('requests and confirms an authenticated email change', () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'old@example.com'),
      );
      final hasher = Argon2idPasswordHasher(
        iterations: 1,
        memoryKiB: 8,
        derivedKeyLength: 16,
      );
      await store.upsertCredentialForAdministration(
        AuthPasswordCredential(
          id: 'credential-1',
          userId: user.id,
          identifier: user.email!,
          passwordHash: hasher.hash('current-password'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      AuthEmailChangeRequest<EngineContext>? sent;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  credentials.password == 'current-password' ? user : null,
            ),
          ],
          passwordHasher: hasher,
          emailChangeSender: (request) => sent = request,
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session')!;
      final signIn = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'old@example.com',
          'password': 'current-password',
          '_csrf': csrfToken,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final sessionCookie = signIn.cookie('test_session') ?? initialCookie;

      final request = await client.postJson(
        '/auth/email/change/request',
        <String, dynamic>{
          'newEmail': 'new@example.com',
          'currentPassword': 'current-password',
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      request.assertStatus(HttpStatus.accepted);
      expect(sent?.newEmail, equals('new@example.com'));

      final confirmation = await client.postJson(
        '/auth/email/change/confirm',
        <String, dynamic>{'token': sent!.token},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      confirmation.assertStatus(HttpStatus.ok);
      expect(confirmation.json()['user']['email'], equals('new@example.com'));
      expect((await store.users.findById(user.id))?.email, 'new@example.com');
    });

    test('lists, unlinks, and deletes the authenticated account', () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final hasher = Argon2idPasswordHasher(
        iterations: 1,
        memoryKiB: 8,
        derivedKeyLength: 16,
      );
      await store.upsertCredentialForAdministration(
        AuthPasswordCredential(
          id: 'credential-1',
          userId: user.id,
          identifier: user.email!,
          passwordHash: hasher.hash('current-password'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: user.id,
          accessToken: 'private-token',
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  credentials.password == 'current-password' ? user : null,
            ),
          ],
          passwordHasher: hasher,
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session')!;
      final signIn = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': user.email,
          'password': 'current-password',
          '_csrf': csrfToken,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final sessionCookie = signIn.cookie('test_session') ?? initialCookie;
      final accounts = await client.get(
        '/auth/accounts',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      accounts.assertStatus(HttpStatus.ok);
      expect(accounts.json()['accounts'].single['provider_id'], 'github');
      expect(accounts.body, isNot(contains('private-token')));

      final unlink = await client.postJson(
        '/auth/accounts/unlink',
        <String, dynamic>{
          'providerId': 'github',
          'providerAccountId': 'github-1',
          'currentPassword': 'current-password',
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      unlink.assertStatus(HttpStatus.ok);
      expect(await store.accounts.listForUser(user.id), isEmpty);

      final deletion = await client.postJson(
        '/auth/account/delete',
        <String, dynamic>{'currentPassword': 'current-password'},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      deletion.assertStatus(HttpStatus.ok);
      final tombstone = await store.users.findById(user.id);
      expect(tombstone, isNotNull);
      expect(tombstone?.email, isNull);
      expect(tombstone?.attributes['deletedAt'], isA<String>());
      expect(await store.purgeTombstonedUserForAdministration(user.id), isTrue);
      expect(await store.users.findById(user.id), isNull);
    });

    test(
      'confirmed deletion validates plugin lifecycle before consuming token',
      () async {
        final store = InMemoryAuthStore();
        final user = AuthUser(id: 'user-1', email: 'user@example.com');
        final hasher = Argon2idPasswordHasher(
          iterations: 1,
          memoryKiB: 8,
          derivedKeyLength: 16,
        );
        final now = DateTime.now().toUtc();
        await store.credentials.register(
          user,
          AuthPasswordCredential(
            id: 'credential-1',
            userId: user.id,
            identifier: user.email!,
            passwordHash: hasher.hash('current-password'),
            createdAt: now,
            updatedAt: now,
          ),
        );
        final organizationStore = InMemoryAuthOrganizationStore();
        final organizations = OrganizationPlugin<EngineContext>(
          store: organizationStore,
        );
        AuthAccountDeletionDelivery<EngineContext>? delivery;
        final manager = AuthManager(
          AuthOptions<EngineContext>(
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            providers: [CredentialsProvider()],
            plugins: [organizations],
            passwordHasher: hasher,
            accountDeletionSender: (sent) {
              delivery = sent;
            },
            enforceCsrf: false,
          ),
        );
        final engine = _authEngine(manager);
        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final csrfResponse = await client.get('/auth/csrf');
        final csrf = csrfResponse.json()['csrfToken'] as String;
        final initialCookie = csrfResponse.cookie('test_session')!;
        final signIn = await client.postJson(
          '/auth/signin/credentials',
          <String, dynamic>{
            'email': user.email,
            'password': 'current-password',
            '_csrf': csrf,
          },
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
          },
        );
        signIn.assertStatus(HttpStatus.ok);
        final sessionCookie = signIn.cookie('test_session') ?? initialCookie;

        final created = await client.postJson(
          '/auth/organization/create',
          <String, dynamic>{'name': 'Acme', 'slug': 'acme', '_csrf': csrf},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        created.assertStatus(HttpStatus.ok);
        final organizationId = created.json()['data']['id'] as String;

        final requested = await client.postJson(
          '/auth/account/delete/request',
          <String, dynamic>{
            'currentPassword': 'current-password',
            '_csrf': csrf,
          },
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        requested.assertStatus(HttpStatus.accepted);
        expect(delivery, isNotNull);

        final confirmed = await client.postJson(
          '/auth/account/delete/confirm',
          <String, dynamic>{'token': delivery!.token, '_csrf': csrf},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        confirmed.assertStatus(HttpStatus.unauthorized);
        expect(confirmed.json()['error'], equals('last_owner'));
        expect(await store.users.findById(user.id), isNotNull);
        expect(
          await organizationStore.findMember(organizationId, user.id),
          isNotNull,
        );
        expect(
          await store.verificationTokens.consume(
            'account_deletion:${user.id}',
            delivery!.token,
          ),
          isNotNull,
        );
      },
    );

    test('accepts providers created from package:server_auth', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            server_auth.CredentialsProvider(
              authorize: (_, _, credentials) async {
                if (credentials.password == 'secret') {
                  return server_auth.AuthUser(
                    id: 'server-auth-user',
                    email: credentials.email,
                  );
                }
                return null;
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      csrfResponse.assertStatus(HttpStatus.ok);
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
      expect(signInResponse.json()['user']['id'], equals('server-auth-user'));
      expect(
        signInResponse.json()['user']['email'],
        equals('user@example.com'),
      );
    });

    test('credentials flow establishes a session', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                if (credentials.password == 'secret') {
                  return AuthUser(
                    id: 'user-1',
                    email: credentials.email,
                    roles: const ['admin'],
                  );
                }
                return null;
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      csrfResponse.assertStatus(HttpStatus.ok);
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
      expect(
        signInResponse.json()['user']['email'],
        equals('user@example.com'),
      );

      final authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);
      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      final sessionBody = _decodeJson(sessionResponse);
      expect(sessionBody, isNotNull);
      expect(sessionBody!['user']['id'], equals('user-1'));
      expect(sessionBody['strategy'], equals('session'));

      final providersResponse = await client.get('/auth/providers');
      providersResponse.assertStatus(HttpStatus.ok);
      final providers = providersResponse.json()['providers'] as List<dynamic>;
      expect(providers.first['id'], equals('credentials'));
    });

    test('credentials register creates a session', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              register: (ctx, provider, credentials) async {
                if (credentials.password == null ||
                    credentials.password!.isEmpty) {
                  return null;
                }
                return AuthUser(id: 'new-user', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
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

      final registerResponse = await client.postJson(
        '/auth/register/credentials',
        {'email': 'new@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      registerResponse.assertStatus(HttpStatus.ok);
      expect(registerResponse.json()['user']['id'], equals('new-user'));

      final authCookie = registerResponse.cookie('test_session');
      expect(authCookie, isNotNull);
      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      final sessionBody = _decodeJson(sessionResponse);
      expect(sessionBody, isNotNull);
      expect(sessionBody!['user']['email'], equals('new@example.com'));
    });

    test('email flow issues verification tokens and signs in', () async {
      late AuthEmailRequest capturedRequest;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            EmailProvider(
              sendVerificationRequest: (ctx, provider, request) async {
                capturedRequest = request;
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

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/email',
        {'email': 'mail@example.com', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      expect(signInResponse.json()['status'], equals('verification_sent'));
      expect(capturedRequest.email, equals('mail@example.com'));
      final emailStateCookie =
          (signInResponse.headers[HttpHeaders.setCookieHeader] ?? [])
              .map(Cookie.fromSetCookieValue)
              .firstWhere(
                (cookie) => cookie.name.startsWith('routed_email_state_'),
              );

      final callbackResponse = await client.get(
        '/auth/callback/email?token=${capturedRequest.token}&email=${capturedRequest.email}',
        headers: {
          HttpHeaders.cookieHeader: [
            _cookieHeader(sessionCookie),
            _cookieHeader(emailStateCookie),
          ],
        },
      );
      callbackResponse.assertStatus(HttpStatus.ok);
      expect(
        callbackResponse.json()['user']['email'],
        equals('mail@example.com'),
      );
    });

    test('email flow invalidates previous verification tokens', () async {
      final requests = <AuthEmailRequest>[];
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            EmailProvider(
              sendVerificationRequest: (ctx, provider, request) async {
                requests.add(request);
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

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      var sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final firstSignIn = await client.postJson(
        '/auth/signin/email',
        {'email': 'mail@example.com', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      sessionCookie = firstSignIn.cookie('test_session') ?? sessionCookie;

      final secondSignIn = await client.postJson(
        '/auth/signin/email',
        {'email': 'mail@example.com', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      sessionCookie = secondSignIn.cookie('test_session') ?? sessionCookie;
      final emailStateCookie =
          (secondSignIn.headers[HttpHeaders.setCookieHeader] ?? [])
              .map(Cookie.fromSetCookieValue)
              .firstWhere(
                (cookie) => cookie.name.startsWith('routed_email_state_'),
              );

      expect(requests.length, equals(2));

      final invalidResponse = await client.get(
        '/auth/callback/email?token=${requests.first.token}&email=${requests.first.email}',
        headers: {
          HttpHeaders.cookieHeader: [
            _cookieHeader(sessionCookie),
            _cookieHeader(emailStateCookie),
          ],
        },
      );
      invalidResponse.assertStatus(HttpStatus.unauthorized);
      expect(invalidResponse.json()['error'], equals('invalid_token'));

      final validResponse = await client.get(
        '/auth/callback/email?token=${requests.last.token}&email=${requests.last.email}',
        headers: {
          HttpHeaders.cookieHeader: [
            _cookieHeader(sessionCookie),
            _cookieHeader(emailStateCookie),
          ],
        },
      );
      validResponse.assertStatus(HttpStatus.ok);
      expect(validResponse.json()['user']['email'], equals('mail@example.com'));
    });

    test('oauth flow exchanges code and establishes session', () async {
      final httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            json.encode({
              'access_token': 'access-123',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/userinfo')) {
          return http.Response(
            json.encode({
              'id': 'oauth-user',
              'email': 'oauth@example.com',
              'email_verified': true,
              'name': 'OAuth User',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            OAuthProvider<Map<String, dynamic>>(
              id: 'oauth',
              name: 'OAuth',
              clientId: 'client-id',
              clientSecret: 'client-secret',
              authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
              tokenEndpoint: Uri.parse('https://auth.test/token'),
              userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
              redirectUri: 'https://app.test/auth/callback/oauth',
              scopes: const ['profile', 'email'],
              profile: (profile) => AuthUser(
                id: profile['id']?.toString() ?? 'unknown',
                email: profile['email']?.toString(),
                name: profile['name']?.toString(),
              ),
            ),
          ],
          httpClient: httpClient,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.get(
        '/auth/signin/oauth',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.movedTemporarily);
      final redirect =
          signInResponse.headers[HttpHeaders.locationHeader]!.first;
      final redirectUri = Uri.parse(redirect);
      expect(redirectUri.host, equals('auth.test'));
      final state = redirectUri.queryParameters['state'];
      expect(state, isNotNull);

      final oauthCookie = signInResponse.cookie('test_session');
      expect(oauthCookie, isNotNull);
      final callbackResponse = await client.get(
        '/auth/callback/oauth?code=code123&state=$state',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(oauthCookie!)],
        },
      );

      callbackResponse.assertStatus(HttpStatus.ok);
      expect(
        callbackResponse.json()['user']['email'],
        equals('oauth@example.com'),
      );
    });

    test('jwt strategy issues token cookie', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'jwt-user', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: 'super-secret'),
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'jwt@example.com', 'password': 'any', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      final tokenCookie = signInResponse.cookie('auth_token');
      expect(tokenCookie, isNotNull);

      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(tokenCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      expect(sessionResponse.json()['strategy'], equals('jwt'));
      expect(sessionResponse.json()['user']['id'], equals('jwt-user'));
    });

    test('session update age refreshes session cookie', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-2', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          sessionUpdateAge: Duration.zero,
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'any', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      var authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 5));

      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      final refreshedCookie = sessionResponse.cookie('test_session');
      expect(refreshedCookie, isNotNull);
      expect(refreshedCookie!.value, isNot(authCookie.value));
    });

    test('jwt update age refreshes token cookie', () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'jwt-user', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.jwt,
          sessionUpdateAge: Duration.zero,
          jwtOptions: const JwtSessionOptions(secret: 'super-secret'),
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'jwt@example.com', 'password': 'any', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      final tokenCookie = signInResponse.cookie('auth_token');
      expect(tokenCookie, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(tokenCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      final refreshedCookie = sessionResponse.cookie('auth_token');
      expect(refreshedCookie, isNotNull);
      expect(refreshedCookie!.value, isNot(tokenCookie.value));
    });
  });
}
