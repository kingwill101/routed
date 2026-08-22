import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _oidcSecret = 'oidc-test-secret';

String _signedOidcToken({String nonce = 'nonce-1', String? issuer}) {
  final key = JsonWebKey.fromJson({
    'kty': 'oct',
    'kid': 'oidc-key',
    'alg': 'HS256',
    'k': base64UrlEncode(utf8.encode(_oidcSecret)).replaceAll('=', ''),
  });
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = <String, dynamic>{
      'sub': 'user-1',
      'email': 'user@example.com',
      'iss': issuer ?? 'https://issuer.test',
      'aud': <String>['client-id'],
      'exp':
          DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          1000,
      'nonce': nonce,
    }
    ..setProtectedHeader('alg', 'HS256')
    ..setProtectedHeader('kid', 'oidc-key')
    ..addRecipient(key, algorithm: 'HS256');
  return builder.build().toCompactSerialization();
}

Map<String, dynamic> _oidcJwk() => <String, dynamic>{
  'kty': 'oct',
  'kid': 'oidc-key',
  'alg': 'HS256',
  'k': base64UrlEncode(utf8.encode(_oidcSecret)).replaceAll('=', ''),
};

void main() {
  test('provider request and verification lifetimes must be positive', () {
    expect(
      () => MagicLinkPlugin<Object>(
        tokenExpiry: Duration.zero,
        sendMagicLink: (_) {},
      ),
      throwsArgumentError,
    );
    expect(
      () => OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        requestTimeout: Duration.zero,
        profile: (profile) => AuthUser(id: 'user-1'),
      ),
      throwsArgumentError,
    );
  });

  test('successful credential callbacks must return a user identity', () async {
    final emptyUser = AuthUser(id: '');
    final credentials = AuthCredentials(
      email: 'user@example.com',
      password: 'test-password',
    );

    expect(
      await authorizeCredentialsSignIn(
        store: CallbackAuthStore(),
        passwordHasher: Argon2idPasswordHasher(),
        provider: CredentialsProvider(authorize: (_, _, _) => emptyUser),
        context: Object(),
        credentials: credentials,
      ),
      isNull,
    );
    expect(
      await authorizeCredentialsRegistration(
        store: CallbackAuthStore(),
        passwordHasher: Argon2idPasswordHasher(),
        provider: CredentialsProvider(register: (_, _, _) => emptyUser),
        context: Object(),
        credentials: credentials,
      ),
      isNull,
    );
  });

  test('resolveAuthProviderById finds provider by exact id', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    expect(resolveAuthProviderById(providers, 'google')?.name, 'Google');
    expect(resolveAuthProviderById(providers, 'missing'), isNull);
    expect(resolveAuthProviderById(providers, '   '), isNull);
  });

  test('resolveAuthProviderByOptionalId handles null and delegates lookup', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];

    expect(resolveAuthProviderByOptionalId(providers, null), isNull);
    expect(
      resolveAuthProviderByOptionalId(providers, 'google')?.name,
      'Google',
    );
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

  test('mergeAuthProvidersById preserves lazy provider iterables', () {
    Iterable<AuthProvider> additional() sync* {
      yield AuthProvider(
        id: 'github',
        name: 'GitHub',
        type: AuthProviderType.oauth,
      );
    }

    final merged = mergeAuthProvidersById(<AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ], additional());

    expect(merged.map((provider) => provider.id), <String>['google', 'github']);
  });

  test(
    'authorizeCredentialsSignIn uses provider callback or store fallback',
    () async {
      final providerUser = AuthUser(id: 'provider-user');
      final adapterUser = AuthUser(id: 'store-user');
      final credentials = AuthCredentials(
        email: 'user@example.com',
        password: 'test-password',
      );

      final providerBacked = CredentialsProvider(
        authorize: (context, provider, credentials) => providerUser,
      );
      final adapterBacked = CredentialsProvider();
      final hasher = Argon2idPasswordHasher();
      final credential = AuthPasswordCredential(
        id: 'credential-1',
        userId: adapterUser.id,
        identifier: 'user@example.com',
        passwordHash: hasher.hash('test-password'),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final store = CallbackAuthStore(
        onFindUserById: (_) => adapterUser,
        onFindCredential: (_) => credential,
      );

      final fromProvider = await authorizeCredentialsSignIn(
        store: store,
        passwordHasher: hasher,
        provider: providerBacked,
        context: Object(),
        credentials: credentials,
      );
      final fromAdapter = await authorizeCredentialsSignIn(
        store: store,
        passwordHasher: hasher,
        provider: adapterBacked,
        context: Object(),
        credentials: credentials,
      );

      expect(fromProvider?.id, equals('provider-user'));
      expect(fromAdapter?.id, equals('store-user'));
    },
  );

  test(
    'authorizeCredentialsRegistration uses provider callback or store fallback',
    () async {
      final providerUser = AuthUser(id: 'provider-register');
      final adapterUser = AuthUser(id: 'store-register');
      final credentials = AuthCredentials(
        email: 'new@example.com',
        password: 'test-password',
      );

      final providerBacked = CredentialsProvider(
        register: (context, provider, credentials) => providerUser,
      );
      final adapterBacked = CredentialsProvider();
      final hasher = Argon2idPasswordHasher();
      final store = CallbackAuthStore(
        onRegisterCredential: (_, credential) {
          expect(credential.passwordHash, isNotEmpty);
          return adapterUser;
        },
      );

      final fromProvider = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: providerBacked,
        context: Object(),
        credentials: credentials,
      );
      final fromAdapter = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: adapterBacked,
        context: Object(),
        credentials: credentials,
      );

      expect(fromProvider?.id, equals('provider-register'));
      expect(fromAdapter?.id, equals('store-register'));
    },
  );

  test(
    'requireAuthorizedCredentialsSignIn throws when credentials are rejected',
    () async {
      await expectLater(
        requireAuthorizedCredentialsSignIn(
          store: CallbackAuthStore(onFindCredential: (_) => null),
          passwordHasher: Argon2idPasswordHasher(),
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(email: 'user@example.com'),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
    },
  );

  test(
    'requireAuthorizedCredentialsRegistration throws custom code when registration fails',
    () async {
      await expectLater(
        requireAuthorizedCredentialsRegistration(
          store: CallbackAuthStore(onRegisterCredential: (_, _) => null),
          passwordHasher: Argon2idPasswordHasher(),
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(email: 'new@example.com'),
          invalidCode: 'registration_blocked',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'registration_blocked',
          ),
        ),
      );
    },
  );

  test('disabled password credentials cannot authenticate', () async {
    final hasher = Argon2idPasswordHasher();
    final user = AuthUser(id: 'disabled-user');
    final credential = AuthPasswordCredential(
      id: 'disabled-credential',
      userId: user.id,
      identifier: 'disabled@example.com',
      passwordHash: hasher.hash('secret'),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      enabled: false,
    );
    final store = CallbackAuthStore(
      onFindUserById: (_) => user,
      onFindCredential: (_) => credential,
    );

    expect(
      await authorizeCredentialsSignIn(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: 'disabled@example.com',
          password: 'secret',
        ),
      ),
      isNull,
    );
  });

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
      authProviderNonceSessionKey('_auth.nonce', 'google'),
      equals('_auth.nonce.google'),
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

  test('resolveOAuthCallbackSessionValues reads provider callback keys', () {
    final store = <String, String>{
      '_auth.state.github': 'state-1',
      '_auth.pkce.github': 'verifier-1',
      '_auth.nonce.github': 'nonce-1',
      '_auth.callback.github': '/dashboard',
    };

    final values = resolveOAuthCallbackSessionValues(
      providerId: 'github',
      stateKey: '_auth.state',
      pkceKey: '_auth.pkce',
      callbackKey: '_auth.callback',
      readSession: (key) => store[key],
    );

    expect(values.expectedState, equals('state-1'));
    expect(values.codeVerifier, equals('verifier-1'));
    expect(values.nonce, equals('nonce-1'));
    expect(values.callbackUrl, equals('/dashboard'));
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
      final store = CallbackAuthStore(
        onFindAccount: (providerId, providerAccountId) {
          return AuthAccount(
            providerId: providerId,
            providerAccountId: providerAccountId,
            userId: 'user-1',
          );
        },
        onFindUserById: (id) async {
          expect(id, equals('user-1'));
          return AuthUser(
            id: 'user-1',
            email: 'old@example.com',
            name: 'Old Name',
            attributes: const <String, dynamic>{'legacy': true},
          );
        },
        onFindUserByEmail: (_) => null,
        onUpdateUser: (user) async {
          updated = true;
          return user;
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        store: store,
        providerId: 'github',
        accountId: 'acct-1',
        mappedUser: AuthUser(
          id: 'provider-user',
          email: 'new@example.com',
          name: 'New Name',
          attributes: const <String, dynamic>{'fresh': true},
        ),
        emailVerified: true,
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
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (_) => null,
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
        store: store,
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
    'resolveOAuthUserForAccount persists first-time user with provider id',
    () async {
      // Discord/GitHub mappers supply a non-empty provider ID; the user must
      // still be created rather than left unpersisted.
      var created = false;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (_) => null,
        onCreateUser: (user) async {
          created = true;
          return AuthUser(id: 'stored-1', email: user.email);
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        store: store,
        providerId: 'discord',
        accountId: 'acct-3',
        mappedUser: AuthUser(
          id: 'discord-uid-12345',
          email: 'new@example.com',
          name: 'New OAuth User',
        ),
      );

      expect(created, isTrue);
      expect(resolved.isNewUser, isTrue);
      expect(resolved.user.id, equals('stored-1'));
    },
  );

  test(
    'resolveOAuthUserForAccount does not link unverified email to local user',
    () async {
      var linkedByEmail = false;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (email) async {
          linkedByEmail = true;
          return AuthUser(id: 'victim-1', email: email);
        },
        onCreateUser: (user) async {
          return AuthUser(id: 'created-oauth', email: user.email);
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        store: store,
        providerId: 'discord',
        accountId: 'acct-4',
        mappedUser: AuthUser(
          id: 'discord-uid-999',
          email: 'victim@example.com',
        ),
        // Discord forwards the email regardless of verification; without an
        // explicit verified assertion we must not match the local victim.
        emailVerified: false,
      );

      expect(linkedByEmail, isFalse);
      expect(resolved.isNewUser, isTrue);
      expect(resolved.user.id, equals('created-oauth'));
      expect(resolved.user.email, isNull);
    },
  );

  test(
    'resolveOAuthUserForAccount does not overwrite linked email when unverified',
    () async {
      AuthUser? updated;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => AuthAccount(
          providerId: 'google',
          providerAccountId: 'acct-6',
          userId: 'local-2',
        ),
        onFindUserById: (_) =>
            AuthUser(id: 'local-2', email: 'trusted@example.com'),
        onUpdateUser: (user) async {
          updated = user;
          return user;
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        store: store,
        providerId: 'google',
        accountId: 'acct-6',
        mappedUser: AuthUser(
          id: 'google-sub-6',
          email: 'attacker@example.com',
          name: 'Updated Name',
        ),
      );

      expect(resolved.user.email, equals('trusted@example.com'));
      expect(updated?.email, equals('trusted@example.com'));
      expect(resolved.user.name, equals('Updated Name'));
    },
  );

  test(
    'resolveOAuthUserForAccount links verified email to existing local user',
    () async {
      String? lookedUpEmail;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (email) async {
          lookedUpEmail = email;
          return AuthUser(id: 'local-1', email: email);
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        store: store,
        providerId: 'google',
        accountId: 'acct-5',
        mappedUser: AuthUser(
          id: 'google-sub-123',
          email: ' EXISTING@example.com ',
        ),
        emailVerified: true,
      );

      expect(resolved.isNewUser, isFalse);
      expect(resolved.user.id, equals('local-1'));
      expect(lookedUpEmail, equals('existing@example.com'));
    },
  );

  test('consumeAuthVerificationToken uses one typed token store', () async {
    final tokenStore = InMemoryAuthVerificationTokenStore();
    final store = CallbackAuthStore(verificationTokens: tokenStore);
    final record = AuthVerificationToken(
      identifier: 'user@example.com',
      token: 'token-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    await tokenStore.save(record);

    final resolved = await consumeAuthVerificationToken(
      store: store,
      identifier: record.identifier,
      token: record.token,
    );
    expect(resolved?.identifier, equals(record.identifier));
    expect(resolved?.token, equals(record.token));
    expect(resolved?.expiresAt, equals(record.expiresAt));
    expect(
      await consumeAuthVerificationToken(
        store: store,
        identifier: record.identifier,
        token: record.token,
      ),
      isNull,
    );
  });

  test(
    'resolveAuthUserByEmailOrCreate returns existing or creates new user',
    () async {
      var created = false;
      final store = CallbackAuthStore(
        onFindUserByEmail: (email) async {
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
        store: store,
        email: 'existing@example.com',
      );
      final createdResult = await resolveAuthUserByEmailOrCreate(
        store: store,
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
    'normalizes email identifiers across credential and email flows',
    () async {
      final store = InMemoryAuthStore();
      final hasher = Argon2idPasswordHasher();
      final registered = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: ' User@EXAMPLE.COM ',
          password: 'test-password',
        ),
      );

      expect(registered?.email, equals('user@example.com'));
      expect(
        (await authorizeCredentialsSignIn(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'USER@example.com',
            password: 'test-password',
          ),
        ))?.id,
        equals(registered?.id),
      );

      final provider = MagicLinkPlugin<Object>(
        tokenGenerator: () => 'case-token',
        sendMagicLink: (_) async {},
      );
      await startAuthEmailSignIn<Object>(
        backend: store,
        provider: provider,
        context: Object(),
        email: ' NEW@Example.COM ',
        callbackUrl: '/after',
        sessionStrategy: AuthSessionStrategy.session,
      );
      final resolved = await resolveAuthEmailVerificationSignIn(
        backend: store,
        providerId: provider.id,
        email: 'new@example.com',
        token: 'case-token',
      );

      expect(resolved?.user.email, equals('new@example.com'));
    },
  );

  test('clearAuthVerificationTokens removes typed store tokens', () async {
    final tokenStore = InMemoryAuthVerificationTokenStore();
    final store = CallbackAuthStore(verificationTokens: tokenStore);
    await tokenStore.save(
      AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'token-1',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );

    await clearAuthVerificationTokens(
      store: store,
      identifier: 'user@example.com',
    );

    final consumed = await tokenStore.consume('user@example.com', 'token-1');
    expect(consumed, isNull);
  });

  test('persistAuthVerificationToken saves to the typed store', () async {
    final tokenStore = InMemoryAuthVerificationTokenStore();
    final store = CallbackAuthStore(verificationTokens: tokenStore);
    final verification = AuthVerificationToken(
      identifier: 'user@example.com',
      token: 'token-2',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    await persistAuthVerificationToken(
      store: store,
      verification: verification,
    );

    final consumed = await tokenStore.consume('user@example.com', 'token-2');
    expect(consumed, isNotNull);
  });

  test(
    'prepareAuthEmailVerificationPayload builds request and pending result',
    () {
      final now = DateTime.utc(2026, 2, 24, 12);
      final provider = MagicLinkPlugin<Object>(
        tokenGenerator: () => 'generated-token',
        tokenExpiry: const Duration(minutes: 15),
        sendMagicLink: (_) async {},
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
      expect(payload.record.email, equals('user@example.com'));
      expect(payload.record.tokenHash, isNot(equals(payload.token)));
      expect(payload.request.callbackUrl, equals('/dashboard'));
      expect(payload.pendingResult.user.email, equals('user@example.com'));
      expect(
        payload.pendingResult.session.strategy,
        equals(AuthSessionStrategy.jwt),
      );
    },
  );

  test(
    'prepareAuthEmailVerificationPayload rejects empty generated tokens',
    () {
      final provider = MagicLinkPlugin<Object>(
        tokenGenerator: () => '  ',
        sendMagicLink: (_) async {},
      );

      expect(
        () => prepareAuthEmailVerificationPayload(
          provider: provider,
          email: 'user@example.com',
          callbackUrl: '/dashboard',
          sessionStrategy: AuthSessionStrategy.jwt,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'startAuthEmailSignIn commits a digest, then delivers and writes callback session',
    () async {
      final sentRequests = <AuthMagicLinkDelivery<Object>>[];
      final provider = MagicLinkPlugin<Object>(
        tokenGenerator: () => 'generated-token',
        sendMagicLink: (delivery) async {
          sentRequests.add(delivery);
        },
      );
      final store = InMemoryAuthStore();
      final session = <String, String>{};

      final payload = await startAuthEmailSignIn<Object>(
        backend: store,
        provider: provider,
        context: Object(),
        email: 'user@example.com',
        callbackUrl: '/after',
        sessionStrategy: AuthSessionStrategy.session,
        callbackKey: '_auth.callback',
        writeSession: (key, value) => session[key] = value,
      );

      expect(payload.token, equals('generated-token'));
      expect(sentRequests, hasLength(1));
      expect(sentRequests.single.email, equals('user@example.com'));
      expect(sentRequests.single.callbackUrl, equals('/after'));
      expect(
        session[authEmailCallbackSessionKey('_auth.callback')],
        equals('/after'),
      );
      final consumed = await store.consumeMagicLink(
        AuthMagicLinkConsumeCommand(
          providerId: provider.id,
          email: 'user@example.com',
          tokenHash: hashOpaqueToken('generated-token'),
          now: DateTime.now(),
          candidate: AuthUser(id: 'generated-user', email: 'user@example.com'),
        ),
      );
      expect(consumed.status, AuthMagicLinkConsumeStatus.consumed);
    },
  );

  test(
    'resolveAuthEmailVerificationSignIn resolves user/new flag and callback url',
    () async {
      final store = InMemoryAuthStore();
      await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      await store.issueMagicLink(
        AuthMagicLinkIssueCommand(
          AuthMagicLinkRecord(
            providerId: 'email',
            email: 'user@example.com',
            tokenHash: hashOpaqueToken('token-1'),
            issuedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          ),
        ),
      );
      final session = <String, String>{
        authEmailCallbackSessionKey('_auth.callback'): '/dashboard',
      };

      final resolved = await resolveAuthEmailVerificationSignIn(
        backend: store,
        providerId: 'email',
        email: 'user@example.com',
        token: 'token-1',
        callbackKey: '_auth.callback',
        readSession: (key) => session[key],
      );

      expect(resolved, isNotNull);
      expect(resolved!.user.id, equals('user-1'));
      expect(resolved.user.attributes['emailVerified'], isTrue);
      expect(resolved.isNewUser, isFalse);
      expect(resolved.callbackUrl, equals('/dashboard'));
    },
  );

  test(
    'resolveAuthEmailVerificationSignIn returns null for invalid token',
    () async {
      final resolved = await resolveAuthEmailVerificationSignIn(
        backend: InMemoryAuthStore(),
        providerId: 'email',
        email: 'missing@example.com',
        token: 'missing-token',
      );

      expect(resolved, isNull);
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
      tokenParams: const <String, String>{
        'resource': 'api',
        'grant_type': 'client_credentials',
        'code': 'overridden-code',
        'redirect_uri': 'https://attacker.test/callback',
        'code_verifier': 'overridden-verifier',
      },
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
    'OAuth provider extension parameters cannot override protocol fields',
    () {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        authorizationParams: const <String, String>{
          'state': 'attacker-state',
          'redirect_uri': 'https://attacker.test/callback',
          'code_challenge': 'attacker-challenge',
          'prompt': 'consent',
        },
        tokenParams: const <String, String>{
          'grant_type': 'client_credentials',
          'code': 'attacker-code',
          'code_verifier': 'attacker-verifier',
          'resource': 'api',
        },
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final authorization = buildOAuthAuthorizationParameters(
        provider,
        state: 'server-state',
        codeChallenge: 'server-challenge',
      );
      expect(authorization['state'], equals('server-state'));
      expect(
        authorization['redirect_uri'],
        equals('https://app.test/callback/example'),
      );
      expect(authorization['code_challenge'], equals('server-challenge'));
      expect(authorization['prompt'], equals('consent'));
    },
  );

  test(
    'resolveOAuthSignInForProvider bounds token endpoint failures',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        profile: (profile) =>
            AuthUser(id: '', email: profile['email']?.toString()),
      );

      await expectLater(
        resolveOAuthSignInForProvider<Object, Map<String, dynamic>>(
          store: CallbackAuthStore(),
          context: Object(),
          provider: provider,
          code: 'auth-code',
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'token_exchange_failed',
          ),
        ),
      );
    },
  );

  test(
    'resolveOAuthSignInForProvider assembles user account and profile payloads',
    () async {
      AuthAccount? linkedAccount;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (_) => null,
        onCreateUser: (user) async =>
            AuthUser(id: 'created-user', email: user.email, name: user.name),
        onLinkAccount: (account) async {
          linkedAccount = account;
          return account;
        },
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
            store: store,
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
                    'email_verified': true,
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
      expect(linkedAccount, same(resolved.account));
      expect(resolved.profile['sub'], equals('sub-123'));
      expect(resolved.profile['email'], equals('user@example.com'));
    },
  );

  test(
    'resolveOAuthSignInForProvider uses fallback account id when profile has no identifier',
    () async {
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
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
        profile: (profile) =>
            AuthUser(id: '', email: profile['email']?.toString()),
      );

      final resolved =
          await resolveOAuthSignInForProvider<Object, Map<String, dynamic>>(
            store: store,
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
                  jsonEncode(<String, dynamic>{
                    'name': 'No Identifier',
                    'email': 'unverified@example.com',
                  }),
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
      expect(resolved.user.email, isNull);
    },
  );

  test(
    'resolveOAuthCallbackSignInForProvider validates state and links account',
    () async {
      AuthAccount? linkedAccount;
      final store = CallbackAuthStore(
        onFindAccount: (_, _) => null,
        onFindUserByEmail: (_) => null,
        onCreateUser: (user) async => AuthUser(id: 'created-user'),
        onLinkAccount: (account) async {
          linkedAccount = account;
          return account;
        },
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
      final session = <String, String>{
        authProviderStateSessionKey('_auth.state', provider.id): 'state-1',
        authProviderPkceSessionKey('_auth.pkce', provider.id): 'verifier-1',
        authProviderCallbackSessionKey('_auth.callback', provider.id):
            '/dashboard',
      };
      final removedSessionKeys = <String>[];

      final resolved =
          await resolveOAuthCallbackSignInForProvider<
            Object,
            Map<String, dynamic>
          >(
            store: store,
            context: Object(),
            provider: provider,
            code: 'auth-code',
            receivedState: 'state-1',
            stateKey: '_auth.state',
            pkceKey: '_auth.pkce',
            callbackKey: '_auth.callback',
            readSession: (key) => session[key],
            removeSession: removedSessionKeys.add,
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
                  jsonEncode(<String, dynamic>{'sub': 'sub-1'}),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              return http.Response('not-found', 404);
            }),
          );

      expect(resolved.callbackUrl, equals('/dashboard'));
      expect(resolved.signIn.account.providerId, equals('example'));
      expect(linkedAccount, isNotNull);
      expect(
        linkedAccount!.providerAccountId,
        equals(resolved.signIn.account.providerAccountId),
      );
      expect(
        removedSessionKeys,
        containsAll(<String>[
          authProviderStateSessionKey('_auth.state', provider.id),
          authProviderPkceSessionKey('_auth.pkce', provider.id),
          authProviderNonceSessionKey('_auth.nonce', provider.id),
          authProviderCallbackSessionKey('_auth.callback', provider.id),
        ]),
      );
    },
  );

  test(
    'resolveOAuthCallbackSignInForProvider throws invalid_state before token exchange',
    () async {
      var linked = false;
      final store = CallbackAuthStore(
        onLinkAccount: (account) async {
          linked = true;
          return account;
        },
      );
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        profile: (_) => AuthUser(id: ''),
      );
      final session = <String, String>{
        authProviderStateSessionKey('_auth.state', provider.id): 'state-1',
      };

      await expectLater(
        resolveOAuthCallbackSignInForProvider<Object, Map<String, dynamic>>(
          store: store,
          context: Object(),
          provider: provider,
          code: 'auth-code',
          receivedState: 'different-state',
          stateKey: '_auth.state',
          pkceKey: '_auth.pkce',
          callbackKey: '_auth.callback',
          readSession: (key) => session[key],
          httpClient: MockClient(
            (_) async => http.Response('should-not-be-called', 500),
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_state',
          ),
        ),
      );
      expect(linked, isFalse);
    },
  );

  test(
    'resolveOAuthCallbackSignInForProvider binds typed OAuth challenges once',
    () async {
      final challengeStore = InMemoryAuthOAuthChallengeStore();
      final session = <String, String>{};
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        profile: (_) => AuthUser(id: ''),
      );
      final started =
          await resolveOAuthAuthorizationStart<Object, Map<String, dynamic>>(
            context: Object(),
            provider: provider,
            stateKey: '_auth.state',
            pkceKey: '_auth.pkce',
            callbackKey: '_auth.callback',
            challengeStore: challengeStore,
            callbackUrl: '/dashboard',
            writeSession: (key, value) => session[key] = value,
          );
      expect(
        session[authProviderStateSessionKey('_auth.state', provider.id)],
        equals(started.state),
      );

      final store = CallbackAuthStore(
        onCreateUser: (user) async => AuthUser(id: 'created-user'),
      );
      final httpClient = MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{'access_token': 'access-token'}),
          200,
        ),
      );
      Future<AuthOAuthCallbackSignInResolution> finish(String browserState) {
        return resolveOAuthCallbackSignInForProvider<
          Object,
          Map<String, dynamic>
        >(
          store: store,
          context: Object(),
          provider: provider,
          code: 'auth-code',
          receivedState: started.state,
          stateKey: '_auth.state',
          pkceKey: '_auth.pkce',
          callbackKey: '_auth.callback',
          readSession: (_) => fail('OAuth challenge read session state'),
          consumeChallenge: challengeStore.consume,
          expectedBrowserState: browserState,
          requireBrowserState: true,
          httpClient: httpClient,
        );
      }

      await expectLater(
        finish('other-browser-state'),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_state',
          ),
        ),
      );

      final resolved = await finish(started.state);
      expect(resolved.callbackUrl, equals('/dashboard'));

      await expectLater(
        finish(started.state),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_state',
          ),
        ),
      );
    },
  );

  test(
    'resolveOAuthCallbackSignInForProvider rejects an account link conflict',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        profile: (_) => AuthUser(id: ''),
      );
      final challengeStore = InMemoryAuthOAuthChallengeStore();
      final started =
          await resolveOAuthAuthorizationStart<Object, Map<String, dynamic>>(
            context: Object(),
            provider: provider,
            stateKey: '_auth.state',
            pkceKey: '_auth.pkce',
            callbackKey: '_auth.callback',
            challengeStore: challengeStore,
            writeSession: (_, _) {},
          );
      final store = CallbackAuthStore(
        onCreateUser: (user) async => AuthUser(id: 'created-user'),
        onLinkAccount: (account) async => AuthAccount(
          providerId: account.providerId,
          providerAccountId: account.providerAccountId,
          userId: 'other-user',
          accessToken: account.accessToken,
          refreshToken: account.refreshToken,
          expiresAt: account.expiresAt,
          metadata: account.metadata,
        ),
      );

      await expectLater(
        resolveOAuthCallbackSignInForProvider<Object, Map<String, dynamic>>(
          store: store,
          context: Object(),
          provider: provider,
          code: 'auth-code',
          receivedState: started.state,
          stateKey: '_auth.state',
          pkceKey: '_auth.pkce',
          callbackKey: '_auth.callback',
          readSession: (_) => throw StateError('session state was used'),
          consumeChallenge: challengeStore.consume,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, dynamic>{'access_token': 'access-token'}),
              200,
            ),
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'account_link_conflict',
          ),
        ),
      );
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

  test('buildOAuthAuthAccount rejects incomplete identity links', () {
    final token = OAuthTokenResponse(
      accessToken: 'access',
      tokenType: 'Bearer',
      expiresIn: null,
      raw: const <String, dynamic>{},
    );

    expect(
      () => buildOAuthAuthAccount(
        providerId: 'github',
        providerAccountId: '',
        userId: 'user-1',
        token: token,
        metadata: const <String, dynamic>{},
      ),
      throwsArgumentError,
    );
    expect(
      () => buildOAuthAuthAccount(
        providerId: 'github',
        providerAccountId: 'account-1',
        userId: '',
        token: token,
        metadata: const <String, dynamic>{},
      ),
      throwsArgumentError,
    );
  });

  test('empty mapped OAuth user IDs use the stable account identity', () async {
    final store = InMemoryAuthStore();

    final resolved = await resolveOAuthUserForAccount(
      store: store,
      providerId: 'github',
      accountId: 'account-1',
      mappedUser: AuthUser(id: '', name: 'Example'),
    );

    expect(resolved.user.id, equals('account-1'));
    expect(resolved.isNewUser, isTrue);
    expect(await store.users.findById('account-1'), same(resolved.user));
  });

  test('OAuth profile updates cannot take a linked user email', () async {
    final store = InMemoryAuthStore();
    await store.users.create(
      AuthUser(id: 'local-user', email: 'trusted@example.com'),
    );
    await store.users.create(
      AuthUser(id: 'other-user', email: 'victim@example.com'),
    );
    await store.accounts.link(
      AuthAccount(
        providerId: 'google',
        providerAccountId: 'google-1',
        userId: 'local-user',
      ),
    );

    final resolved = await resolveOAuthUserForAccount(
      store: store,
      providerId: 'google',
      accountId: 'google-1',
      mappedUser: AuthUser(
        id: 'google-user',
        email: 'victim@example.com',
        name: 'Updated Name',
      ),
      emailVerified: true,
    );

    expect(resolved.user.id, equals('local-user'));
    expect(resolved.user.email, equals('trusted@example.com'));
    expect(resolved.userUpdated, isFalse);
    expect(
      (await store.users.findByEmail('victim@example.com'))?.id,
      equals('other-user'),
    );
  });

  test(
    'resolveOAuthSignInForProvider bounds malformed profile parsing',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
        redirectUri: 'https://app.test/callback/example',
        profileParser: (_) => throw const FormatException('unexpected detail'),
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      await expectLater(
        resolveOAuthSignInForProvider<Object, Map<String, dynamic>>(
          store: CallbackAuthStore(),
          context: Object(),
          provider: provider,
          code: 'auth-code',
          httpClient: MockClient((request) async {
            if (request.url.path == '/token') {
              return http.Response(
                jsonEncode(<String, dynamic>{
                  'access_token': 'token-1',
                  'token_type': 'Bearer',
                }),
                200,
                headers: const <String, String>{
                  'content-type': 'application/json',
                },
              );
            }
            return http.Response(
              jsonEncode(<String, dynamic>{'sub': 'subject-1'}),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'profile_invalid',
          ),
        ),
      );
    },
  );

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

  test('prepareOAuthAuthorizationStart generates an OIDC nonce', () {
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'oidc',
      name: 'OIDC',
      type: AuthProviderType.oidc,
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/oidc',
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    final start = prepareOAuthAuthorizationStart(provider);

    expect(start.nonce, isNotNull);
    expect(start.parameters['nonce'], equals(start.nonce));
  });

  test(
    'resolveOAuthAuthorizationStart persists session keys and returns authorization uri',
    () async {
      final persisted = <String, String>{};
      String? seenState;
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
        onStateGenerated: (_, _, state) {
          seenState = state;
        },
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final resolved =
          await resolveOAuthAuthorizationStart<Object, Map<String, dynamic>>(
            context: Object(),
            provider: provider,
            stateKey: '_auth.state',
            pkceKey: '_auth.pkce',
            callbackKey: '_auth.callback',
            callbackUrl: '/dashboard',
            writeSession: (key, value) => persisted[key] = value,
          );

      expect(resolved.state, isNotEmpty);
      expect(resolved.codeVerifier, isNotNull);
      expect(resolved.parameters['state'], equals(resolved.state));
      expect(
        resolved.authorizationUri.toString(),
        contains('https://auth.test/authorize?'),
      );
      expect(seenState, equals(resolved.state));
      expect(
        persisted[authProviderStateSessionKey('_auth.state', 'example')],
        equals(resolved.state),
      );
      expect(
        persisted[authProviderPkceSessionKey('_auth.pkce', 'example')],
        equals(resolved.codeVerifier),
      );
      expect(
        persisted[authProviderCallbackSessionKey('_auth.callback', 'example')],
        equals('/dashboard'),
      );
    },
  );

  test(
    'resolveOAuthAuthorizationStart skips callback key when callback url missing',
    () async {
      final persisted = <String, String>{};
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        usePkce: false,
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      await resolveOAuthAuthorizationStart<Object, Map<String, dynamic>>(
        context: Object(),
        provider: provider,
        stateKey: '_auth.state',
        pkceKey: '_auth.pkce',
        callbackKey: '_auth.callback',
        writeSession: (key, value) => persisted[key] = value,
      );

      expect(
        persisted.containsKey(
          authProviderCallbackSessionKey('_auth.callback', 'example'),
        ),
        isFalse,
      );
      expect(
        persisted.containsKey(
          authProviderPkceSessionKey('_auth.pkce', 'example'),
        ),
        isFalse,
      );
      expect(
        persisted.containsKey(
          authProviderStateSessionKey('_auth.state', 'example'),
        ),
        isTrue,
      );
    },
  );

  test(
    'resolveOAuthAuthorizationStart rejects a non-positive challenge TTL',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        profile: (_) => AuthUser(id: 'user-1'),
      );

      await expectLater(
        resolveOAuthAuthorizationStart<Object, Map<String, dynamic>>(
          context: Object(),
          provider: provider,
          stateKey: '_auth.state',
          pkceKey: '_auth.pkce',
          callbackKey: '_auth.callback',
          challengeStore: InMemoryAuthOAuthChallengeStore(),
          challengeTtl: Duration.zero,
          writeSession: (_, _) => fail('session state should not be used'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'loadOAuthProfile verifies id_token claims when no userinfo endpoint',
    () async {
      final idToken = _signedOidcToken();

      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'oidc',
        name: 'OIDC',
        type: AuthProviderType.oidc,
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/oidc',
        oidcIssuer: Uri.parse('https://issuer.test'),
        oidcJwksUri: Uri.parse('https://issuer.test/jwks'),
        oidcAlgorithms: const ['HS256'],
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
        oidcNonce: 'nonce-1',
        httpClient: MockClient((request) async {
          expect(request.url.path, equals('/jwks'));
          return http.Response(
            jsonEncode(<String, dynamic>{
              'keys': [_oidcJwk()],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      expect(profile['sub'], equals('user-1'));
      expect(profile['email'], equals('user@example.com'));
    },
  );

  test('loadOAuthProfile rejects unsigned OIDC id_tokens', () async {
    final header = base64UrlEncode(
      utf8.encode('{"alg":"none"}'),
    ).replaceAll('=', '');
    final payload = base64UrlEncode(
      utf8.encode(
        '{"sub":"attacker","iss":"https://issuer.test","aud":["client-id"],"exp":4102444800,"nonce":"nonce-1"}',
      ),
    ).replaceAll('=', '');
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'oidc',
      name: 'OIDC',
      type: AuthProviderType.oidc,
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/oidc',
      oidcIssuer: Uri.parse('https://issuer.test'),
      oidcJwksUri: Uri.parse('https://issuer.test/jwks'),
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    await expectLater(
      loadOAuthProfile(
        provider,
        token: OAuthTokenResponse(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresIn: 3600,
          raw: <String, dynamic>{'id_token': '$header.$payload.'},
        ),
        oidcNonce: 'nonce-1',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'keys': [_oidcJwk()],
            }),
            200,
          ),
        ),
      ),
      throwsA(isA<AuthFlowException>()),
    );
  });

  test('loadOAuthProfile rejects an OIDC nonce mismatch', () async {
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'oidc',
      name: 'OIDC',
      type: AuthProviderType.oidc,
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/oidc',
      oidcIssuer: Uri.parse('https://issuer.test'),
      oidcJwksUri: Uri.parse('https://issuer.test/jwks'),
      oidcAlgorithms: const ['HS256'],
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    await expectLater(
      loadOAuthProfile(
        provider,
        token: OAuthTokenResponse(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresIn: 3600,
          raw: <String, dynamic>{'id_token': _signedOidcToken(nonce: 'wrong')},
        ),
        oidcNonce: 'expected',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'keys': [_oidcJwk()],
            }),
            200,
          ),
        ),
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'oidc_nonce_mismatch',
        ),
      ),
    );
  });

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
