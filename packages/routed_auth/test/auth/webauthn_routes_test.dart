import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
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

Future<_PasswordlessUnlinkFixture> _passwordlessUnlinkFixture({
  DateTime Function()? clock,
  bool supportsAtomicMutation = true,
}) async {
  final user = AuthUser(id: 'user-1', email: 'user@example.com');
  final memoryStore = InMemoryAuthStore();
  final AuthStore store = supportsAtomicMutation
      ? memoryStore
      : _NonAtomicAuthStore(memoryStore);
  await memoryStore.users.create(user);
  await memoryStore.accounts.link(
    AuthAccount(
      providerId: 'github',
      providerAccountId: 'github-1',
      userId: user.id,
    ),
  );
  await memoryStore.webAuthnAuthenticators.create(
    WebAuthnAuthenticator(
      credentialId: 'passkey-1',
      publicKey: 'cose-key',
      counter: 0,
      userId: user.id,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  final webAuthnProvider = WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'localhost',
      name: 'Local test',
      origin: 'http://localhost',
    ),
  );
  final manager = AuthManager(
    AuthOptions<EngineContext>(
      store: store,
      storeMode: supportsAtomicMutation
          ? AuthStoreMode.ephemeral
          : AuthStoreMode.durable,
      runtimeMode: AuthRuntimeMode.localDevelopment,
      providers: <AuthProvider>[
        CredentialsProvider(authorize: (_, _, _) => user),
      ],
      plugins: <AuthServerPlugin<EngineContext>>[
        WebAuthnPlugin<EngineContext>(provider: webAuthnProvider),
      ],
      enforceCsrf: false,
    ),
    clock: clock,
  );
  final engine = _engine(manager);
  await engine.initialize();
  final client = TestClient(RoutedRequestHandler(engine));
  final csrfResponse = await client.get('/auth/csrf');
  final csrf = csrfResponse.json()['csrfToken'] as String;
  final initialCookie = csrfResponse.cookie('test_session')!;
  final signIn = await client.postJson(
    '/auth/signin/credentials',
    <String, dynamic>{
      'email': user.email,
      'password': 'external-proof',
      '_csrf': csrf,
    },
    headers: <String, List<String>>{
      HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
    },
  );
  signIn.assertStatus(HttpStatus.ok);
  final sessionCookie = signIn.cookie('test_session') ?? initialCookie;
  return _PasswordlessUnlinkFixture(
    client: client,
    store: memoryStore,
    sessionHeaders: <String, List<String>>{
      HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
    },
  );
}

final class _PasswordlessUnlinkFixture {
  const _PasswordlessUnlinkFixture({
    required this.client,
    required this.store,
    required this.sessionHeaders,
  });

  final TestClient client;
  final InMemoryAuthStore store;
  final Map<String, List<String>> sessionHeaders;
}

Engine _engine(AuthManager manager) {
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [RoutedSessionsProvider(_sessionConfig())],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

OAuthProvider<Map<String, dynamic>> _oauthProvider(String id) =>
    OAuthProvider<Map<String, dynamic>>(
      id: id,
      name: id,
      clientId: 'client',
      clientSecret: 'secret',
      authorizationEndpoint: Uri.https('$id.test', '/authorize'),
      tokenEndpoint: Uri.https('$id.test', '/token'),
      profile: (_) => AuthUser(id: 'unused'),
      redirectUri: 'http://localhost/auth/callback/$id',
    );

void main() {
  test(
    'WebAuthn feature routes share session and browser protections',
    () async {
      final user = AuthUser(
        id: 'user-1',
        email: 'user@example.com',
        name: 'Example User',
      );
      final store = InMemoryAuthStore();
      await store.users.create(user);
      final webAuthnProvider = WebAuthnProvider(
        getUserInfo: (_, _, _) => null,
        getRelyingParty: (_, _) => const WebAuthnRelyingParty(
          id: 'localhost',
          name: 'Local test',
          origin: 'http://localhost',
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(authorize: (_, _, _) => user),
            _oauthProvider('github'),
            webAuthnProvider,
          ],
          plugins: [WebAuthnPlugin<EngineContext>(provider: webAuthnProvider)],
          enforceCsrf: false,
        ),
      );
      final engine = _engine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session');
      expect(initialCookie, isNotNull);
      final signIn = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': user.email,
          'password': 'secret',
          '_csrf': csrf,
        },
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie!)],
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final sessionCookie = signIn.cookie('test_session');
      expect(sessionCookie, isNotNull);
      final sessionHeaders = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
      };

      final options = await client.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
        headers: sessionHeaders,
      );
      options.assertStatus(HttpStatus.ok);
      expect(options.json()['challenge'], isA<String>());
      expect(options.json()['rp']['id'], 'localhost');

      final list = await client.get(
        '/auth/webauthn/credentials',
        headers: sessionHeaders,
      );
      list.assertStatus(HttpStatus.ok);
      expect(list.json()['credentials'], isEmpty);

      await store.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: 'credential-1',
          publicKey: 'cose-key',
          counter: 0,
          userId: user.id,
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Old name',
        ),
      );
      final renamed = await client.postJson(
        '/auth/webauthn/credentials/rename',
        <String, dynamic>{'credentialId': 'credential-1', 'name': 'New name'},
        headers: sessionHeaders,
      );
      renamed.assertStatus(HttpStatus.ok);
      expect(renamed.json()['credential']['name'], 'New name');

      final lastMethod = await client.postJson(
        '/auth/webauthn/credentials/delete',
        const <String, dynamic>{'credentialId': 'credential-1'},
        headers: sessionHeaders,
      );
      lastMethod.assertStatus(HttpStatus.forbidden);
      expect(lastMethod.json()['error'], 'last_authentication_method');
      expect(
        await store.webAuthnAuthenticators.findByCredentialId('credential-1'),
        isNotNull,
      );

      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: user.id,
        ),
      );
      final deleted = await client.postJson(
        '/auth/webauthn/credentials/delete',
        const <String, dynamic>{'credentialId': 'credential-1'},
        headers: sessionHeaders,
      );
      deleted.assertStatus(HttpStatus.ok);
      expect(
        await store.webAuthnAuthenticators.findByCredentialId('credential-1'),
        isNull,
      );

      final unauthenticated = TestClient(RoutedRequestHandler(engine));
      addTearDown(unauthenticated.close);
      final rejected = await unauthenticated.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
      );
      rejected.assertStatus(HttpStatus.unauthorized);
      expect(rejected.json()['error'], 'unauthorized');

      final crossSite = await client.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
        headers: <String, List<String>>{
          ...sessionHeaders,
          'Origin': ['https://evil.example'],
        },
      );
      crossSite.assertStatus(HttpStatus.forbidden);
      expect(crossSite.json()['error'], 'invalid_origin');
    },
  );

  test(
    'fresh passwordless authentication can unlink with passkey fallback',
    () async {
      final fixture = await _passwordlessUnlinkFixture();
      addTearDown(fixture.client.close);

      final response = await fixture.client.postJson(
        '/auth/accounts/unlink',
        const <String, dynamic>{
          'providerId': 'github',
          'providerAccountId': 'github-1',
        },
        headers: fixture.sessionHeaders,
      );

      response.assertStatus(HttpStatus.ok);
      expect(await fixture.store.accounts.listForUser('user-1'), isEmpty);
      expect(
        await fixture.store.webAuthnAuthenticators.findByCredentialId(
          'passkey-1',
        ),
        isNotNull,
      );
    },
  );

  test('stale passwordless authentication requires a new proof', () async {
    final fixture = await _passwordlessUnlinkFixture(
      clock: () => DateTime.utc(2100),
    );
    addTearDown(fixture.client.close);

    final response = await fixture.client.postJson(
      '/auth/accounts/unlink',
      const <String, dynamic>{
        'providerId': 'github',
        'providerAccountId': 'github-1',
      },
      headers: fixture.sessionHeaders,
    );

    response.assertStatus(HttpStatus.forbidden);
    expect(response.json()['error'], 'recent_authentication_required');
    expect(await fixture.store.accounts.find('github', 'github-1'), isNotNull);
  });

  test('unlink is unavailable when the store cannot join atomically', () async {
    final fixture = await _passwordlessUnlinkFixture(
      supportsAtomicMutation: false,
    );
    addTearDown(fixture.client.close);

    final response = await fixture.client.postJson(
      '/auth/accounts/unlink',
      const <String, dynamic>{
        'providerId': 'github',
        'providerAccountId': 'github-1',
      },
      headers: fixture.sessionHeaders,
    );

    response.assertStatus(HttpStatus.serviceUnavailable);
    expect(
      response.json()['error'],
      'authentication_method_mutation_unavailable',
    );
    expect(await fixture.store.accounts.listForUser('user-1'), hasLength(1));
  });
}

final class _NonAtomicAuthStore
    implements
        AuthStore,
        AuthWebAuthnStoreCapabilities,
        AuthUserDeletionCoordinatorHost {
  const _NonAtomicAuthStore(this.delegate);

  final InMemoryAuthStore delegate;

  @override
  AuthAccountStore get accounts => delegate.accounts;
  @override
  AuthCredentialStore get credentials => delegate.credentials;
  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      delegate.deviceAuthorizations;
  @override
  AuthEmailChangeTokenStore get emailChangeTokens => delegate.emailChangeTokens;
  @override
  AuthEmailOtpStore get emailOtps => delegate.emailOtps;
  @override
  AuthJwtVersionStore get jwtVersions => delegate.jwtVersions;
  @override
  AuthOAuthChallengeStore get oauthChallenges => delegate.oauthChallenges;
  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      delegate.passwordResetTokens;
  @override
  AuthSessionStore get sessions => delegate.sessions;
  @override
  AuthUserStore get users => delegate.users;
  @override
  AuthVerificationTokenStore get verificationTokens =>
      delegate.verificationTokens;
  @override
  AuthWebAuthnChallengeStore get webAuthnChallenges =>
      delegate.webAuthnChallenges;
  @override
  AuthWebAuthnAuthenticatorStore get webAuthnAuthenticators =>
      delegate.webAuthnAuthenticators;
  @override
  AuthUserDeletionCoordinator get userDeletionCoordinator =>
      delegate.userDeletionCoordinator;

  @override
  void bindUserDeletionPlanContributors(
    Iterable<AuthUserDeletionPlanContributor> contributors,
  ) => delegate.bindUserDeletionPlanContributors(contributors);
}
