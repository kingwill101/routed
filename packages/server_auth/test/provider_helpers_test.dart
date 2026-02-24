import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('resolveAuthProviderById finds provider by exact id', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    expect(resolveAuthProviderById(providers, 'google')?.name, 'Google');
    expect(resolveAuthProviderById(providers, 'missing'), isNull);
    expect(resolveAuthProviderById(providers, '   '), isNull);
  });

  test('authProviderSummaries returns stable provider payloads', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];

    expect(
      authProviderSummaries(providers),
      equals(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'google', 'name': 'Google', 'type': 'oidc'},
      ]),
    );
  });

  test('mergeAuthProvidersById appends only missing providers', () {
    final base = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];
    final additional = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google 2', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    final merged = mergeAuthProvidersById(base, additional);

    expect(
      merged.map((provider) => provider.id),
      equals(<String>['google', 'github']),
    );
    expect(merged.first.name, equals('Google'));
  });

  test(
    'authorizeCredentialsSignIn uses provider callback or adapter fallback',
    () async {
      final providerUser = AuthUser(id: 'provider-user');
      final adapterUser = AuthUser(id: 'adapter-user');
      final credentials = AuthCredentials(
        email: 'user@example.com',
        password: 'pw',
      );

      final providerBacked = CredentialsProvider(
        authorize: (context, provider, credentials) => providerUser,
      );
      final adapterBacked = CredentialsProvider();
      final adapter = CallbackAuthAdapter(
        onVerifyCredentials: (_) => adapterUser,
      );

      final fromProvider = await authorizeCredentialsSignIn(
        adapter: adapter,
        provider: providerBacked,
        context: Object(),
        credentials: credentials,
      );
      final fromAdapter = await authorizeCredentialsSignIn(
        adapter: adapter,
        provider: adapterBacked,
        context: Object(),
        credentials: credentials,
      );

      expect(fromProvider?.id, equals('provider-user'));
      expect(fromAdapter?.id, equals('adapter-user'));
    },
  );

  test(
    'authorizeCredentialsRegistration uses provider callback or adapter fallback',
    () async {
      final providerUser = AuthUser(id: 'provider-register');
      final adapterUser = AuthUser(id: 'adapter-register');
      final credentials = AuthCredentials(
        email: 'new@example.com',
        password: 'pw',
      );

      final providerBacked = CredentialsProvider(
        register: (context, provider, credentials) => providerUser,
      );
      final adapterBacked = CredentialsProvider();
      final adapter = CallbackAuthAdapter(
        onRegisterCredentials: (_) => adapterUser,
      );

      final fromProvider = await authorizeCredentialsRegistration(
        adapter: adapter,
        provider: providerBacked,
        context: Object(),
        credentials: credentials,
      );
      final fromAdapter = await authorizeCredentialsRegistration(
        adapter: adapter,
        provider: adapterBacked,
        context: Object(),
        credentials: credentials,
      );

      expect(fromProvider?.id, equals('provider-register'));
      expect(fromAdapter?.id, equals('adapter-register'));
    },
  );

  test('auth provider session key helpers compose stable keys', () {
    expect(
      authProviderStateSessionKey('_auth.state', 'github'),
      equals('_auth.state.github'),
    );
    expect(
      authProviderPkceSessionKey('_auth.pkce', 'google'),
      equals('_auth.pkce.google'),
    );
    expect(
      authProviderCallbackSessionKey('_auth.callback', 'discord'),
      equals('_auth.callback.discord'),
    );
    expect(
      authEmailCallbackSessionKey('_auth.callback'),
      equals('_auth.callback.email'),
    );
  });

  test('ensureOAuthStateMatches validates callback state', () {
    expect(
      () => ensureOAuthStateMatches(
        expectedState: 'state-1',
        receivedState: 'state-1',
      ),
      returnsNormally,
    );
    expect(
      () => ensureOAuthStateMatches(
        expectedState: 'state-1',
        receivedState: 'state-2',
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'invalid_state',
        ),
      ),
    );
  });

  test(
    'resolveOAuthUserForAccount updates linked users when profile changes',
    () async {
      var updated = false;
      final adapter = CallbackAuthAdapter(
        onGetAccount: (providerId, providerAccountId) {
          return AuthAccount(
            providerId: providerId,
            providerAccountId: providerAccountId,
            userId: 'user-1',
          );
        },
        onGetUserById: (id) async {
          expect(id, equals('user-1'));
          return AuthUser(
            id: 'user-1',
            email: 'old@example.com',
            name: 'Old Name',
            attributes: const <String, dynamic>{'legacy': true},
          );
        },
        onGetUserByEmail: (_) => null,
        onUpdateUser: (user) async {
          updated = true;
          return user;
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        adapter: adapter,
        providerId: 'github',
        accountId: 'acct-1',
        mappedUser: AuthUser(
          id: 'provider-user',
          email: 'new@example.com',
          name: 'New Name',
          attributes: const <String, dynamic>{'fresh': true},
        ),
      );

      expect(resolved.isNewUser, isFalse);
      expect(resolved.userUpdated, isTrue);
      expect(resolved.user.id, equals('user-1'));
      expect(resolved.user.email, equals('new@example.com'));
      expect(resolved.user.attributes['legacy'], isTrue);
      expect(resolved.user.attributes['fresh'], isTrue);
      expect(updated, isTrue);
    },
  );

  test(
    'resolveOAuthUserForAccount creates user when no records resolve',
    () async {
      var created = false;
      final adapter = CallbackAuthAdapter(
        onGetAccount: (_, _) => null,
        onGetUserByEmail: (_) => null,
        onCreateUser: (user) async {
          created = true;
          return AuthUser(
            id: 'created-user',
            email: user.email,
            name: user.name,
            attributes: user.attributes,
          );
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        adapter: adapter,
        providerId: 'google',
        accountId: 'acct-2',
        mappedUser: AuthUser(
          id: '',
          email: 'new@example.com',
          name: 'New User',
        ),
      );

      expect(resolved.isNewUser, isTrue);
      expect(resolved.userUpdated, isFalse);
      expect(resolved.user.id, equals('created-user'));
      expect(created, isTrue);
    },
  );

  test(
    'consumeAuthVerificationToken falls back to secondary token store',
    () async {
      final adapter = CallbackAuthAdapter(
        onUseVerificationToken: (_, _) => null,
      );
      final tokenStore = InMemoryAuthVerificationTokenStore();
      final record = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'token-1',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      await tokenStore.save(record);

      final resolved = await consumeAuthVerificationToken(
        adapter: adapter,
        tokenStore: tokenStore,
        identifier: 'user@example.com',
        token: 'token-1',
      );
      expect(resolved, isNotNull);
      expect(resolved!.identifier, equals('user@example.com'));
    },
  );

  test(
    'resolveAuthUserByEmailOrCreate returns existing or creates new user',
    () async {
      var created = false;
      final adapter = CallbackAuthAdapter(
        onGetUserByEmail: (email) async {
          if (email == 'existing@example.com') {
            return AuthUser(id: 'existing-1', email: email);
          }
          return null;
        },
        onCreateUser: (user) async {
          created = true;
          return AuthUser(id: 'created-1', email: user.email);
        },
      );

      final existing = await resolveAuthUserByEmailOrCreate(
        adapter: adapter,
        email: 'existing@example.com',
      );
      final createdResult = await resolveAuthUserByEmailOrCreate(
        adapter: adapter,
        email: 'new@example.com',
      );

      expect(existing.isNewUser, isFalse);
      expect(existing.user.id, equals('existing-1'));
      expect(createdResult.isNewUser, isTrue);
      expect(createdResult.user.id, equals('created-1'));
      expect(created, isTrue);
    },
  );

  test(
    'clearAuthVerificationTokens removes adapter and store tokens',
    () async {
      var deletedIdentifier = '';
      final adapter = CallbackAuthAdapter(
        onDeleteVerificationTokens: (identifier) async {
          deletedIdentifier = identifier;
        },
      );
      final tokenStore = InMemoryAuthVerificationTokenStore();
      await tokenStore.save(
        AuthVerificationToken(
          identifier: 'user@example.com',
          token: 'token-1',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

      await clearAuthVerificationTokens(
        adapter: adapter,
        tokenStore: tokenStore,
        identifier: 'user@example.com',
      );

      expect(deletedIdentifier, equals('user@example.com'));
      final consumed = await tokenStore.use('user@example.com', 'token-1');
      expect(consumed, isNull);
    },
  );

  test('persistAuthVerificationToken saves to adapter and store', () async {
    AuthVerificationToken? savedToAdapter;
    final adapter = CallbackAuthAdapter(
      onSaveVerificationToken: (token) async {
        savedToAdapter = token;
      },
    );
    final tokenStore = InMemoryAuthVerificationTokenStore();
    final verification = AuthVerificationToken(
      identifier: 'user@example.com',
      token: 'token-2',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    await persistAuthVerificationToken(
      adapter: adapter,
      tokenStore: tokenStore,
      verification: verification,
    );

    expect(savedToAdapter, isNotNull);
    final consumed = await tokenStore.use('user@example.com', 'token-2');
    expect(consumed, isNotNull);
  });

  test(
    'prepareAuthEmailVerificationPayload builds request and pending result',
    () {
      final now = DateTime.utc(2026, 2, 24, 12);
      final provider = EmailProvider(
        tokenGenerator: () => 'generated-token',
        tokenExpiry: const Duration(minutes: 15),
        sendVerificationRequest: (context, provider, request) async {},
      );

      final payload = prepareAuthEmailVerificationPayload(
        provider: provider,
        email: 'user@example.com',
        callbackUrl: '/dashboard',
        sessionStrategy: AuthSessionStrategy.jwt,
        now: now,
      );

      expect(payload.token, equals('generated-token'));
      expect(payload.expiresAt, equals(now.add(const Duration(minutes: 15))));
      expect(payload.verification.identifier, equals('user@example.com'));
      expect(payload.request.callbackUrl, equals('/dashboard'));
      expect(payload.pendingResult.user.email, equals('user@example.com'));
      expect(
        payload.pendingResult.session.strategy,
        equals(AuthSessionStrategy.jwt),
      );
    },
  );

  test('exchangeOAuthAuthorizationCode uses provider token settings', () async {
    late http.Request captured;
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'example',
      name: 'Example',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/example',
      scopes: const <String>['openid', 'profile'],
      tokenParams: const <String, String>{'resource': 'api'},
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    final token = await exchangeOAuthAuthorizationCode(
      provider,
      code: 'auth-code',
      codeVerifier: 'pkce-verifier',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': 'token-1',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(token.accessToken, equals('token-1'));
    expect(captured.bodyFields['grant_type'], equals('authorization_code'));
    expect(captured.bodyFields['code'], equals('auth-code'));
    expect(
      captured.bodyFields['redirect_uri'],
      equals('https://app.test/callback/example'),
    );
    expect(captured.bodyFields['scope'], equals('openid profile'));
    expect(captured.bodyFields['code_verifier'], equals('pkce-verifier'));
    expect(captured.bodyFields['resource'], equals('api'));
  });

  test(
    'resolveOAuthSignInForProvider assembles user account and profile payloads',
    () async {
      final adapter = CallbackAuthAdapter(
        onGetAccount: (_, _) => null,
        onGetUserByEmail: (_) => null,
        onCreateUser: (user) async =>
            AuthUser(id: 'created-user', email: user.email, name: user.name),
      );
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
        redirectUri: 'https://app.test/callback/example',
        profile: (profile) => AuthUser(
          id: '',
          email: profile['email']?.toString(),
          name: profile['name']?.toString(),
        ),
      );

      final resolved =
          await resolveOAuthSignInForProvider<Object, Map<String, dynamic>>(
            adapter: adapter,
            context: Object(),
            provider: provider,
            code: 'auth-code',
            codeVerifier: 'pkce-verifier',
            httpClient: MockClient((request) async {
              if (request.url.path == '/token') {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'access_token': 'token-1',
                    'token_type': 'Bearer',
                    'refresh_token': 'refresh-1',
                    'expires_in': 3600,
                  }),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              if (request.url.path == '/userinfo') {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'sub': 'sub-123',
                    'email': 'user@example.com',
                    'name': 'Example User',
                  }),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              return http.Response('not-found', 404);
            }),
          );

      expect(resolved.isNewUser, isTrue);
      expect(resolved.userUpdated, isFalse);
      expect(resolved.user.id, equals('created-user'));
      expect(resolved.user.email, equals('user@example.com'));
      expect(resolved.account.providerId, equals('example'));
      expect(resolved.account.providerAccountId, equals('sub-123'));
      expect(resolved.account.userId, equals('created-user'));
      expect(resolved.account.accessToken, equals('token-1'));
      expect(resolved.account.refreshToken, equals('refresh-1'));
      expect(resolved.profile['sub'], equals('sub-123'));
      expect(resolved.profile['email'], equals('user@example.com'));
    },
  );

  test(
    'resolveOAuthSignInForProvider uses fallback account id when profile has no identifier',
    () async {
      final adapter = CallbackAuthAdapter(
        onGetAccount: (_, _) => null,
        onCreateUser: (user) async => AuthUser(id: 'created-user'),
      );
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
        redirectUri: 'https://app.test/callback/example',
        profile: (_) => AuthUser(id: ''),
      );

      final resolved =
          await resolveOAuthSignInForProvider<Object, Map<String, dynamic>>(
            adapter: adapter,
            context: Object(),
            provider: provider,
            code: 'auth-code',
            httpClient: MockClient((request) async {
              if (request.url.path == '/token') {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'access_token': 'token-1',
                    'token_type': 'Bearer',
                    'expires_in': 3600,
                  }),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              if (request.url.path == '/userinfo') {
                return http.Response(
                  jsonEncode(<String, dynamic>{'name': 'No Identifier'}),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              return http.Response('not-found', 404);
            }),
            fallbackAccountId: () => 'fallback-account',
          );

      expect(resolved.isNewUser, isTrue);
      expect(resolved.account.providerAccountId, equals('fallback-account'));
      expect(resolved.account.userId, equals('created-user'));
    },
  );

  test('buildOAuthAuthAccount maps oauth token payload into account', () {
    final account = buildOAuthAuthAccount(
      providerId: 'github',
      providerAccountId: 'acct-1',
      userId: 'user-1',
      token: OAuthTokenResponse(
        accessToken: 'access',
        tokenType: 'Bearer',
        expiresIn: 3600,
        refreshToken: 'refresh',
        raw: const <String, dynamic>{},
      ),
      expiresAt: DateTime.utc(2026, 2, 24, 12),
      metadata: const <String, dynamic>{'login': 'octocat'},
    );

    expect(account.providerId, equals('github'));
    expect(account.providerAccountId, equals('acct-1'));
    expect(account.userId, equals('user-1'));
    expect(account.accessToken, equals('access'));
    expect(account.refreshToken, equals('refresh'));
    expect(account.expiresAt, equals(DateTime.utc(2026, 2, 24, 12)));
    expect(account.metadata['login'], equals('octocat'));
  });

  test(
    'buildOAuthAuthorizationParameters includes scopes, pkce and callback',
    () {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        scopes: const <String>['openid', 'profile'],
        authorizationParams: const <String, String>{'prompt': 'consent'},
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final params = buildOAuthAuthorizationParameters(
        provider,
        state: 'state-123',
        codeChallenge: 'challenge-xyz',
        callbackUrl: '/dashboard',
      );

      expect(params['response_type'], equals('code'));
      expect(params['client_id'], equals('client-id'));
      expect(
        params['redirect_uri'],
        equals('https://app.test/callback/example'),
      );
      expect(params['state'], equals('state-123'));
      expect(params['scope'], equals('openid profile'));
      expect(params['code_challenge'], equals('challenge-xyz'));
      expect(params['code_challenge_method'], equals('S256'));
      expect(params['callbackUrl'], equals('/dashboard'));
      expect(params['prompt'], equals('consent'));
    },
  );

  test('prepareOAuthAuthorizationStart generates state, pkce and params', () {
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'example',
      name: 'Example',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/example',
      scopes: const <String>['openid'],
      usePkce: true,
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    final start = prepareOAuthAuthorizationStart(
      provider,
      callbackUrl: '/dashboard',
    );

    expect(start.state, isNotEmpty);
    expect(start.codeVerifier, isNotNull);
    expect(start.codeChallenge, isNotNull);
    expect(start.parameters['state'], equals(start.state));
    expect(start.parameters['code_challenge'], equals(start.codeChallenge));
    expect(start.parameters['callbackUrl'], equals('/dashboard'));
  });

  test(
    'loadOAuthProfile decodes id_token claims when no userinfo endpoint',
    () async {
      final header = base64UrlEncode(
        utf8.encode('{"alg":"none","typ":"JWT"}'),
      ).replaceAll('=', '');
      final payload = base64UrlEncode(
        utf8.encode('{"sub":"user-1","email":"user@example.com"}'),
      ).replaceAll('=', '');
      final idToken = '$header.$payload.';

      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'oidc',
        name: 'OIDC',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/oidc',
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final profile = await loadOAuthProfile(
        provider,
        token: OAuthTokenResponse(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresIn: 3600,
          raw: <String, dynamic>{'id_token': idToken},
        ),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(profile['sub'], equals('user-1'));
      expect(profile['email'], equals('user@example.com'));
    },
  );

  test(
    'loadOAuthProfile maps userinfo callback failures to AuthFlowException',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'custom',
        name: 'Custom',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
        userInfoRequest: (token, client, endpoint) => throw StateError('boom'),
        redirectUri: 'https://app.test/callback/custom',
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      await expectLater(
        loadOAuthProfile(
          provider,
          token: OAuthTokenResponse(
            accessToken: 'access-token',
            tokenType: 'Bearer',
            expiresIn: 3600,
            raw: const <String, dynamic>{},
          ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'userinfo_failed',
          ),
        ),
      );
    },
  );
}
