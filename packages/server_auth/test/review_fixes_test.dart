import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('OAuth provider PKCE accepts the unpadded RFC 7636 S256 vector', () {
    final feature = OAuthProviderModeFeature<Object>(
      clientStore: InMemoryOAuthClientStore(),
      authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
      accessTokenStore: InMemoryOAuthAccessTokenStore(),
      options: const OAuthProviderModeOptions(),
    );

    expect(
      feature.validatePkce(
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        'S256',
      ),
      isTrue,
    );
  });

  test('verification cleanup deletes only the failed issuance', () async {
    final store = InMemoryAuthVerificationTokenStore();
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));
    const identifier = 'account_deletion:user-1';
    await store.save(
      AuthVerificationToken(
        identifier: identifier,
        token: 'first-token',
        expiresAt: expiresAt,
      ),
    );
    await store.save(
      AuthVerificationToken(
        identifier: identifier,
        token: 'second-token',
        expiresAt: expiresAt,
      ),
    );

    expect(await store.deleteToken(identifier, 'first-token'), isTrue);
    expect(await store.consume(identifier, 'first-token'), isNull);
    expect(await store.consume(identifier, 'second-token'), isNotNull);
  });

  group('P1: Reject failed email updates', () {
    late InMemoryAuthStore store;

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'old@example.com');
      await _seedUser(store, 'u2', 'taken@example.com');
    });

    test('confirmEmailChange does not report success or revoke sessions when '
        'update returns null', () async {
      // Seed a session so we can verify it is NOT revoked on failure.
      final now = DateTime.now().toUtc();
      await store.sessions.create(
        AuthSessionRecord(
          id: 's1',
          tokenHash: hashOpaqueToken('token-1'),
          userId: 'u1',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
          lastUsedAt: now,
          authenticationMethod: 'password',
        ),
      );

      // Manually place a bound pending-email token so we can call
      // confirmEmailChange with a target email that belongs to another user.
      await store.emailChangeTokens.save(
        AuthEmailChangeToken(
          userId: 'u1',
          newEmail: 'taken@example.com',
          token: 'valid-token',
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );

      // u2 already owns 'taken@example.com', so the atomic email update fails.
      expect(
        () => confirmEmailChange(
          store: store,
          tokenIdentifier: 'email_change:u1',
          token: 'valid-token',
          newEmail: 'taken@example.com',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'email_already_in_use',
          ),
        ),
      );

      // The session must still be active — no false-success revocation.
      final sessions = await store.sessions.listForUser('u1');
      expect(sessions, hasLength(1));
    });
  });

  group('P1: Enforce configured OAuth scopes', () {
    late InMemoryOAuthClientStore clientStore;
    late InMemoryOAuthAuthorizationCodeStore codeStore;
    late OAuthProviderModeFeature<Object> feature;

    setUp(() async {
      clientStore = InMemoryOAuthClientStore();
      codeStore = InMemoryOAuthAuthorizationCodeStore();
      feature = OAuthProviderModeFeature<Object>(
        clientStore: clientStore,
        authorizationCodeStore: codeStore,
        accessTokenStore: InMemoryOAuthAccessTokenStore(),
        options: const OAuthProviderModeOptions(
          supportedScopes: ['openid', 'profile', 'email'],
          requirePkce: false,
        ),
      );
      feature.configure(
        AuthServerPluginContext<Object>(store: InMemoryAuthStore()),
      );

      await clientStore.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: _clientSecretHash('secret'),
          name: 'Test Client',
          redirectUris: ['https://app.example.com/callback'],
          scopes: ['openid', 'profile'],
          grantTypes: ['authorization_code', 'client_credentials'],
        ),
      );
    });

    test('authorize rejects scope not granted to the client', () async {
      final result = feature.endpoints.firstWhere(
        (e) => e.id == 'oauth_provider.authorize',
      );
      expect(
        () => result.invoke(
          AuthOperationInvocation<Object>(
            context: Object(),
            user: AuthUser(id: 'user-1'),
          ),
          {
            'client_id': 'client-1',
            'redirect_uri': 'https://app.example.com/callback',
            'response_type': 'code',
            'scope': 'openid email',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_scope',
          ),
        ),
      );
    });

    test('authorize rejects scope not supported by the provider', () async {
      final result = feature.endpoints.firstWhere(
        (e) => e.id == 'oauth_provider.authorize',
      );
      expect(
        () => result.invoke(
          AuthOperationInvocation<Object>(
            context: Object(),
            user: AuthUser(id: 'user-1'),
          ),
          {
            'client_id': 'client-1',
            'redirect_uri': 'https://app.example.com/callback',
            'response_type': 'code',
            'scope': 'openid admin',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_scope',
          ),
        ),
      );
    });

    test(
      'authorize accepts scopes within the client and provider allow-list',
      () async {
        final result = feature.endpoints.firstWhere(
          (e) => e.id == 'oauth_provider.authorize',
        );
        final response =
            await result.invoke(
                  AuthOperationInvocation<Object>(
                    context: Object(),
                    user: AuthUser(id: 'user-1'),
                  ),
                  {
                    'client_id': 'client-1',
                    'redirect_uri': 'https://app.example.com/callback',
                    'response_type': 'code',
                    'scope': 'openid profile',
                    'state': 'client-state',
                  },
                )
                as AuthEndpointRedirect;
        expect(result.method, AuthOperationMethod.get);
        expect(response.location.host, 'app.example.com');
        expect(response.location.queryParameters['state'], 'client-state');
        final code = response.location.queryParameters['code'];
        expect(code, isNotNull);

        final consumed = await codeStore.consume(code!);
        expect(consumed?.scope, equals('openid profile'));
      },
    );

    test('client_credentials grant rejects unapproved scope', () async {
      final result = feature.endpoints.firstWhere(
        (e) => e.id == 'oauth_provider.token',
      );
      expect(
        () => result.invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          {
            'grant_type': 'client_credentials',
            'client_id': 'client-1',
            'client_secret': 'secret',
            'scope': 'admin',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_scope',
          ),
        ),
      );
    });
  });

  group('P1: Keep refresh tokens valid beyond access-token expiry', () {
    late OAuthProviderModeFeature<Object> feature;

    setUp(() async {
      final clientStore = InMemoryOAuthClientStore();
      feature = OAuthProviderModeFeature<Object>(
        clientStore: clientStore,
        authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
        accessTokenStore: InMemoryOAuthAccessTokenStore(),
        options: const OAuthProviderModeOptions(
          accessTokenLifetime: Duration(milliseconds: 1),
          refreshTokenLifetime: Duration(hours: 1),
        ),
      );
      feature.configure(
        AuthServerPluginContext<Object>(store: InMemoryAuthStore()),
      );

      await clientStore.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: _clientSecretHash('secret'),
          name: 'Test Client',
          redirectUris: ['https://app.example.com/callback'],
          scopes: ['openid'],
          grantTypes: ['client_credentials', 'refresh_token'],
        ),
      );
    });

    test(
      'refresh token remains usable after the access token has expired',
      () async {
        final tokenEndpoint = feature.endpoints.firstWhere(
          (e) => e.id == 'oauth_provider.token',
        );

        final tokenResult =
            await tokenEndpoint.invoke(
                  AuthOperationInvocation<Object>(
                    context: Object(),
                    user: null,
                  ),
                  {
                    'grant_type': 'client_credentials',
                    'client_id': 'client-1',
                    'client_secret': 'secret',
                    'scope': 'openid',
                  },
                )
                as Map<String, dynamic>;

        final refreshToken = tokenResult['refresh_token'] as String;
        expect(refreshToken, isNotEmpty);

        // Wait for the access token to expire (1 ms lifetime).
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final refreshResult =
            await tokenEndpoint.invoke(
                  AuthOperationInvocation<Object>(
                    context: Object(),
                    user: null,
                  ),
                  {
                    'grant_type': 'refresh_token',
                    'client_id': 'client-1',
                    'client_secret': 'secret',
                    'refresh_token': refreshToken,
                  },
                )
                as Map<String, dynamic>;

        expect(refreshResult['access_token'], isNotNull);
        expect(refreshResult['refresh_token'], isNotNull);
      },
    );

    test('concurrent refresh rotation allows exactly one request', () async {
      final tokenEndpoint = feature.endpoints.firstWhere(
        (endpoint) => endpoint.id == 'oauth_provider.token',
      );
      final issued =
          await tokenEndpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {
                  'grant_type': 'client_credentials',
                  'client_id': 'client-1',
                  'client_secret': 'secret',
                  'scope': 'openid',
                },
              )
              as Map<String, dynamic>;
      final refreshToken = issued['refresh_token'] as String;

      Future<Object> refresh() async {
        try {
          return await tokenEndpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {
                  'grant_type': 'refresh_token',
                  'client_id': 'client-1',
                  'client_secret': 'secret',
                  'refresh_token': refreshToken,
                },
              ) ??
              Object();
        } catch (error) {
          return error;
        }
      }

      final outcomes = await Future.wait([refresh(), refresh()]);
      expect(outcomes.whereType<Map<String, dynamic>>(), hasLength(1));
      expect(
        outcomes.whereType<AuthFlowException>().single.code,
        equals('invalid_grant'),
      );
    });

    test('configured refresh-token use limit is enforced', () async {
      final clientStore = InMemoryOAuthClientStore();
      await clientStore.create(
        OAuthClient(
          clientId: 'limited-client',
          clientSecretHash: _clientSecretHash('secret'),
          name: 'Limited Client',
          redirectUris: const ['https://app.example.com/callback'],
          scopes: const ['openid'],
          grantTypes: const ['client_credentials', 'refresh_token'],
        ),
      );
      final limited = OAuthProviderModePlugin<Object>(
        clientStore: clientStore,
        authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
        accessTokenStore: InMemoryOAuthAccessTokenStore(),
        options: const OAuthProviderModeOptions(maxRefreshTokenUses: 1),
      )..configure(AuthServerPluginContext<Object>(store: InMemoryAuthStore()));
      final endpoint = limited.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.token',
      );
      final issued =
          await endpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {
                  'grant_type': 'client_credentials',
                  'client_id': 'limited-client',
                  'client_secret': 'secret',
                  'scope': 'openid',
                },
              )
              as Map<String, dynamic>;
      final refreshed =
          await endpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {
                  'grant_type': 'refresh_token',
                  'client_id': 'limited-client',
                  'client_secret': 'secret',
                  'refresh_token': issued['refresh_token'],
                },
              )
              as Map<String, dynamic>;
      expect(
        () => endpoint.invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          {
            'grant_type': 'refresh_token',
            'client_id': 'limited-client',
            'client_secret': 'secret',
            'refresh_token': refreshed['refresh_token'],
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_grant',
          ),
        ),
      );
    });
  });

  group('P2: OAuth provider options define protocol behavior', () {
    test('uses configured endpoint paths and allowlists', () async {
      final clientStore = InMemoryOAuthClientStore();
      await clientStore.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: _clientSecretHash('secret'),
          name: 'Test Client',
          redirectUris: const ['https://app.example.com/callback'],
          scopes: const ['openid'],
          grantTypes: const ['authorization_code', 'client_credentials'],
        ),
      );
      final plugin = OAuthProviderModePlugin<Object>(
        clientStore: clientStore,
        authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
        accessTokenStore: InMemoryOAuthAccessTokenStore(),
        options: const OAuthProviderModeOptions(
          authorizationEndpoint: '/identity/authorize',
          tokenEndpoint: '/identity/token',
          userInfoEndpoint: '/identity/userinfo',
          jwksEndpoint: '/identity/jwks',
          introspectionEndpoint: '/identity/introspect',
          supportedGrantTypes: ['authorization_code'],
          supportedResponseTypes: [],
          requirePkce: false,
        ),
      )..configure(AuthServerPluginContext<Object>(store: InMemoryAuthStore()));
      final paths = {
        for (final endpoint in plugin.endpoints) endpoint.id: endpoint.path,
      };
      expect(paths['oauth_provider.authorize'], '/identity/authorize');
      expect(paths['oauth_provider.token'], '/identity/token');
      expect(paths['oauth_provider.userinfo'], '/identity/userinfo');
      expect(paths['oauth_provider.jwks'], '/identity/jwks');
      expect(paths['oauth_provider.introspect'], '/identity/introspect');

      final tokenEndpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.token',
      );
      expect(
        () => tokenEndpoint.invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          {
            'grant_type': 'client_credentials',
            'client_id': 'client-1',
            'client_secret': 'secret',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'unsupported_grant_type',
          ),
        ),
      );

      final authorizeEndpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.authorize',
      );
      expect(
        () => authorizeEndpoint.invoke(
          AuthOperationInvocation<Object>(
            context: Object(),
            user: AuthUser(id: 'user-1'),
          ),
          {
            'client_id': 'client-1',
            'redirect_uri': 'https://app.example.com/callback',
            'response_type': 'code',
            'scope': 'openid',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'unsupported_response_type',
          ),
        ),
      );
    });
  });

  group('P1: OAuth bearer identity remains authoritative', () {
    late InMemoryAuthStore store;
    late InMemoryOAuthClientStore clientStore;
    late InMemoryOAuthAccessTokenStore tokenStore;
    late OAuthProviderModePlugin<Object> plugin;

    setUp(() async {
      store = InMemoryAuthStore();
      await store.users.create(
        AuthUser(
          id: 'user-1',
          email: 'real@example.com',
          name: 'Real Name',
          attributes: const {
            'sub': 'attacker',
            'email': 'attacker@example.com',
            'name': 'Attacker',
            'picture': 'https://attacker.invalid/image',
            'custom': 'kept',
          },
        ),
      );
      tokenStore = InMemoryOAuthAccessTokenStore();
      clientStore = InMemoryOAuthClientStore();
      await clientStore.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: _clientSecretHash('secret'),
          name: 'Test Client',
          redirectUris: const ['https://app.example.com/callback'],
          scopes: const ['openid', 'profile', 'email'],
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('access-token'),
          clientId: 'client-1',
          userId: 'user-1',
          scope: 'openid profile email',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      plugin = OAuthProviderModePlugin<Object>(
        clientStore: clientStore,
        authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
        accessTokenStore: tokenStore,
        options: const OAuthProviderModeOptions(
          userInfoClaimsByScope: {
            'profile': ['custom', 'sub', 'email'],
          },
        ),
      )..configure(AuthServerPluginContext<Object>(store: store));
    });

    test('UserInfo attributes cannot replace protocol claims', () async {
      final endpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.userinfo',
      );
      final response =
          await endpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {'_authorization': 'Bearer access-token'},
              )
              as Map<String, dynamic>;
      expect(response['sub'], equals('user-1'));
      expect(response['email'], equals('real@example.com'));
      expect(response['name'], equals('Real Name'));
      expect(response['picture'], isNull);
      expect(response['custom'], equals('kept'));
    });

    test('disabled users cannot use an otherwise valid access token', () async {
      await store.disable('user-1', reason: 'security');
      final endpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.userinfo',
      );
      expect(
        () => endpoint.invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          {'_authorization': 'Bearer access-token'},
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_token',
          ),
        ),
      );
    });

    test('UserInfo emits claims only for granted scopes', () async {
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('profile-token'),
          clientId: 'client-1',
          userId: 'user-1',
          scope: 'profile',
          expiresAt: expiresAt,
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('email-token'),
          clientId: 'client-1',
          userId: 'user-1',
          scope: 'email',
          expiresAt: expiresAt,
        ),
      );
      final endpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.userinfo',
      );

      final profile =
          await endpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {'_authorization': 'Bearer profile-token'},
              )
              as Map<String, dynamic>;
      expect(profile['sub'], equals('user-1'));
      expect(profile['name'], equals('Real Name'));
      expect(profile['custom'], equals('kept'));
      expect(profile, isNot(contains('email')));

      final email =
          await endpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                {'_authorization': 'Bearer email-token'},
              )
              as Map<String, dynamic>;
      expect(email['sub'], equals('user-1'));
      expect(email['email'], equals('real@example.com'));
      expect(email, isNot(contains('name')));
      expect(email, isNot(contains('picture')));
      expect(email, isNot(contains('custom')));
    });

    test('deleting a client revokes its tokens immediately', () async {
      final endpoint = plugin.endpoints.firstWhere(
        (value) => value.id == 'oauth_provider.clients.delete',
      );
      await endpoint.invoke(
        AuthOperationInvocation<Object>(
          context: Object(),
          user: AuthUser(id: 'admin', roles: const ['admin']),
        ),
        {'client_id': 'client-1'},
      );

      expect(await clientStore.findById('client-1'), isNull);
      expect(await tokenStore.findByToken('access-token'), isNull);
    });
  });

  group('P1: Account lifecycle safety boundaries', () {
    test('username credentials support deletion and unlink safety', () async {
      final store = InMemoryAuthStore();
      final now = DateTime.now().toUtc();
      await store.credentials.register(
        AuthUser(id: 'user-1'),
        AuthPasswordCredential(
          id: 'credential-1',
          userId: 'user-1',
          identifier: 'alice',
          passwordHash: 'hash:current-password',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: 'user-1',
        ),
      );

      final initiated = await initiateAccountDeletion(
        store: store,
        passwordHasher: const _TestPasswordHasher(),
        userId: 'user-1',
        password: 'current-password',
        generateToken: () => 'delete-token',
      );

      expect(initiated.confirmationToken, equals('delete-token'));
      expect(
        await canUnlinkProvider(
          store: store,
          userId: 'user-1',
          providerId: 'github',
          providerAccountId: 'github-1',
        ),
        isTrue,
      );
    });

    test('cannot unlink the only authentication method', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: 'user-1',
        ),
      );

      expect(
        () => unlinkProviderAccount(
          store: store,
          userId: 'user-1',
          providerId: 'github',
          providerAccountId: 'github-1',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'last_authentication_method',
          ),
        ),
      );
      expect(await store.accounts.find('github', 'github-1'), isNotNull);
    });

    test(
      'deletion fails before consuming a token without atomic support',
      () async {
        final tokens = InMemoryAuthVerificationTokenStore();
        final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
        await tokens.save(
          AuthVerificationToken(
            identifier: 'account_deletion:user-1',
            token: 'delete-token',
            expiresAt: expiresAt,
          ),
        );
        final store = CallbackAuthStore(verificationTokens: tokens);

        expect(
          () => confirmAccountDeletion(
            store: store,
            userId: 'user-1',
            token: 'delete-token',
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'account_deletion_unavailable',
            ),
          ),
        );
        expect(
          await tokens.consume('account_deletion:user-1', 'delete-token'),
          isNotNull,
        );
      },
    );
  });

  group('P2: Preserve SameSite in cookie copies', () {
    test('copyWith preserves SameSite.strict', () {
      const policy = AuthCookiePolicy(sameSite: SameSite.strict);
      final copied = policy.copyWith(httpOnly: false);
      expect(copied.httpOnly, isFalse);
      expect(copied.sameSite, equals(SameSite.strict));
    });

    test('copyWith preserves SameSite.none', () {
      const policy = AuthCookiePolicy(sameSite: SameSite.none);
      final copied = policy.copyWith(secure: false);
      expect(copied.secure, isFalse);
      expect(copied.sameSite, equals(SameSite.none));
    });

    test('copyWith allows overriding SameSite', () {
      const policy = AuthCookiePolicy(sameSite: SameSite.lax);
      final copied = policy.copyWith(sameSite: SameSite.strict);
      expect(copied.sameSite, equals(SameSite.strict));
    });

    test('copyWith preserves and explicitly clears the cookie domain', () {
      const policy = AuthCookiePolicy(domain: '.example.com');

      expect(policy.copyWith(httpOnly: false).domain, '.example.com');
      expect(policy.copyWith(clearDomain: true).domain, isNull);
    });
  });

  group('P2: InMemoryAuthStore exposes AuthAccountStateStore', () {
    test('store implements AuthAccountStateStore', () {
      final store = InMemoryAuthStore();
      expect(store, isA<AuthAccountStateStore>());
    });

    test('recordFailedLogin and lockout work through the store', () async {
      final store = InMemoryAuthStore();
      const policy = AuthAccountPolicy(maxLoginAttempts: 2);

      await store.recordFailedLogin('u1', policy: policy);
      expect((await store.find('u1'))?.isLocked(), isFalse);

      await store.recordFailedLogin('u1', policy: policy);
      expect((await store.find('u1'))?.isLocked(), isTrue);
    });

    test('resetFailedAttempts clears lockout through the store', () async {
      final store = InMemoryAuthStore();
      const policy = AuthAccountPolicy(maxLoginAttempts: 1);

      await store.recordFailedLogin('u1', policy: policy);
      expect((await store.find('u1'))?.isLocked(), isTrue);

      await store.resetFailedAttempts('u1');
      expect((await store.find('u1'))?.isLocked(), isFalse);
      expect((await store.find('u1'))?.failedLoginAttempts, isZero);
    });

    test('disable and enable work through the store', () async {
      final store = InMemoryAuthStore();
      await store.disable('u1', reason: 'abuse');
      expect((await store.find('u1'))?.disabled, isTrue);
      expect((await store.find('u1'))?.disabledReason, equals('abuse'));

      await store.enable('u1');
      expect((await store.find('u1'))?.disabled, isFalse);
    });
  });
}

String _clientSecretHash(String secret) =>
    sha256.convert(utf8.encode(secret)).toString();

// --- Helpers ---

Future<void> _seedUser(
  InMemoryAuthStore store,
  String id,
  String email, {
  List<String> roles = const ['user'],
}) async {
  final existing = await store.users.findById(id);
  if (existing != null) return;
  final user = AuthUser(id: id, email: email, roles: roles);
  final result = await store.credentials.register(
    user,
    AuthPasswordCredential(
      id: 'cred-$id',
      userId: id,
      identifier: email,
      passwordHash: 'hash:password123',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  if (result == null) {
    await store.users.create(user);
  }
}

final class _TestPasswordHasher implements PasswordHasher {
  const _TestPasswordHasher();

  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}
