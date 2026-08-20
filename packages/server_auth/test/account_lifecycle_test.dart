import 'dart:io';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthAccountPolicy', () {
    test('development defaults allow unverified sign-in', () {
      const policy = AuthAccountPolicy.development;
      expect(policy.requireEmailVerification, isFalse);
      expect(policy.allowUnverifiedSignIn, isTrue);
    });

    test('production defaults require email verification', () {
      const policy = AuthAccountPolicy.production;
      expect(policy.requireEmailVerification, isTrue);
      expect(policy.allowUnverifiedSignIn, isFalse);
    });

    test('AuthAccountState serializes and deserializes', () {
      final state = AuthAccountState(
        userId: 'u1',
        emailVerified: true,
        disabled: true,
        disabledReason: 'spam',
        failedLoginAttempts: 3,
      );
      final json = state.toJson();
      final restored = AuthAccountState.fromJson(json);
      expect(restored.userId, equals('u1'));
      expect(restored.emailVerified, isTrue);
      expect(restored.disabled, isTrue);
      expect(restored.disabledReason, equals('spam'));
      expect(restored.failedLoginAttempts, equals(3));
    });

    test('isLocked returns true when lockout has not expired', () {
      final state = AuthAccountState(
        userId: 'u1',
        lockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      );
      expect(state.isLocked(), isTrue);
    });

    test('isLocked returns false when lockout has expired', () {
      final state = AuthAccountState(
        userId: 'u1',
        lockedUntil: DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        ),
      );
      expect(state.isLocked(), isFalse);
    });

    test('canAuthenticate respects disabled, locked, and banned states', () {
      const policy = AuthAccountPolicy();
      final now = DateTime.now().toUtc();

      final active = AuthAccountState(userId: 'u1');
      expect(active.canAuthenticate(now: now, policy: policy), isTrue);

      final disabled = AuthAccountState(userId: 'u2', disabled: true);
      expect(disabled.canAuthenticate(now: now, policy: policy), isFalse);

      final locked = AuthAccountState(
        userId: 'u3',
        lockedUntil: now.add(const Duration(minutes: 5)),
      );
      expect(locked.canAuthenticate(now: now, policy: policy), isFalse);

      final banned = AuthAdminUserState(userId: 'u4', banned: true);
      expect(banned.isBanned(), isTrue);
    });
  });

  group('InMemoryAuthAccountStateStore', () {
    late InMemoryAuthAccountStateStore store;

    setUp(() {
      store = InMemoryAuthAccountStateStore();
    });

    test('find returns null for unknown user', () async {
      expect(await store.find('unknown'), isNull);
    });

    test('recordLogin creates state and resets failed attempts', () async {
      await store.recordFailedLogin('u1', policy: const AuthAccountPolicy());
      final afterFail = await store.find('u1');
      expect(afterFail?.failedLoginAttempts, equals(1));

      await store.recordLogin('u1');
      final afterLogin = await store.find('u1');
      expect(afterLogin?.failedLoginAttempts, equals(0));
      expect(afterLogin?.lastLoginAt, isNotNull);
    });

    test('recordFailedLogin locks account after max attempts', () async {
      const policy = AuthAccountPolicy(maxLoginAttempts: 3);
      await store.recordFailedLogin('u1', policy: policy);
      await store.recordFailedLogin('u1', policy: policy);
      final afterTwo = await store.find('u1');
      expect(afterTwo?.isLocked(), isFalse);

      await store.recordFailedLogin('u1', policy: policy);
      final afterThree = await store.find('u1');
      expect(afterThree?.isLocked(), isTrue);
    });

    test('disable and enable toggle the disabled flag', () async {
      await store.disable('u1', reason: 'spam');
      final disabled = await store.find('u1');
      expect(disabled?.disabled, isTrue);
      expect(disabled?.disabledReason, equals('spam'));

      await store.enable('u1');
      final enabled = await store.find('u1');
      expect(enabled?.disabled, isFalse);
    });

    test('markEmailVerified sets emailVerified', () async {
      await store.markEmailVerified('u1');
      final state = await store.find('u1');
      expect(state?.emailVerified, isTrue);
    });

    test('unlock clears lockout', () async {
      const policy = AuthAccountPolicy(maxLoginAttempts: 1);
      await store.recordFailedLogin('u1', policy: policy);
      expect((await store.find('u1'))?.isLocked(), isTrue);

      await store.unlock('u1');
      expect((await store.find('u1'))?.isLocked(), isFalse);
    });

    test('findInactiveAccounts returns users with no recent login', () async {
      // Create a user that never logged in
      await store.upsert(AuthAccountState(userId: 'u2'));
      final inactive = await store.findInactiveAccounts(inactiveDays: 1);
      // u2 never logged in, should be inactive
      expect(inactive.map((s) => s.userId), contains('u2'));
    });
  });

  group('Email change flow', () {
    late InMemoryAuthStore store;
    const hasher = _Hasher();

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'old@example.com');
    });

    test('initiateEmailChange rejects wrong password', () async {
      expect(
        () => initiateEmailChange(
          store: store,
          passwordHasher: hasher,
          userId: 'u1',
          currentPassword: 'wrong',
          newEmail: 'new@example.com',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_current_password',
          ),
        ),
      );
    });

    test('initiateEmailChange rejects invalid email', () async {
      expect(
        () => initiateEmailChange(
          store: store,
          passwordHasher: hasher,
          userId: 'u1',
          currentPassword: 'password123',
          newEmail: 'not-an-email',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_email',
          ),
        ),
      );
    });

    test('initiateEmailChange succeeds with correct password', () async {
      final result = await initiateEmailChange(
        store: store,
        passwordHasher: hasher,
        userId: 'u1',
        currentPassword: 'password123',
        newEmail: 'new@example.com',
      );
      expect(result.userId, equals('u1'));
      expect(result.oldEmail, equals('old@example.com'));
      expect(result.newEmail, equals('new@example.com'));
      expect(result.verificationToken, isNotEmpty);
    });

    test('confirmEmailChange updates email and revokes sessions', () async {
      final initiated = await initiateEmailChange(
        store: store,
        passwordHasher: hasher,
        userId: 'u1',
        currentPassword: 'password123',
        newEmail: 'new@example.com',
      );

      // Create a session to verify revocation
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

      final confirmed = await confirmEmailChange(
        store: store,
        tokenIdentifier: 'email_change:u1',
        token: initiated.verificationToken,
        newEmail: 'new@example.com',
      );

      expect(confirmed.oldEmail, equals('old@example.com'));
      expect(confirmed.newEmail, equals('new@example.com'));
      expect(confirmed.sessionsRevoked, equals(1));

      // Verify email was updated
      final user = await store.users.findById('u1');
      expect(user?.email, equals('new@example.com'));
    });

    test('confirmEmailChange rejects invalid token', () async {
      expect(
        () => confirmEmailChange(
          store: store,
          tokenIdentifier: 'email_change:u1',
          token: 'bad-token',
          newEmail: 'new@example.com',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_email_change_token',
          ),
        ),
      );
    });
  });

  group('Account deletion flow', () {
    late InMemoryAuthStore store;
    const hasher = _Hasher();

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'user@example.com');
      await store.credentials.updatePasswordForUser(
        userId: 'u1',
        passwordHash: 'hash:password123',
        updatedAt: DateTime.now().toUtc(),
      );
    });

    test('initiateAccountDeletion rejects wrong password', () async {
      expect(
        () => initiateAccountDeletion(
          store: store,
          passwordHasher: hasher,
          userId: 'u1',
          password: 'wrong',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'invalid_password',
          ),
        ),
      );
    });

    test('initiateAccountDeletion succeeds with correct password', () async {
      final result = await initiateAccountDeletion(
        store: store,
        passwordHasher: hasher,
        userId: 'u1',
        password: 'password123',
      );
      expect(result.userId, equals('u1'));
      expect(result.confirmationToken, isNotEmpty);
    });

    test('confirmAccountDeletion removes user and all data', () async {
      // Create sessions and linked accounts
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
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );

      final initiated = await initiateAccountDeletion(
        store: store,
        passwordHasher: hasher,
        userId: 'u1',
        password: 'password123',
      );

      final confirmed = await confirmAccountDeletion(
        store: store,
        userId: 'u1',
        token: initiated.confirmationToken,
      );

      expect(confirmed.deleted, isTrue);

      // Verify user is gone
      expect(await store.users.findById('u1'), isNull);

      // Verify sessions are revoked
      final sessions = await store.sessions.listForUser('u1');
      expect(sessions.every((s) => s.revokedAt != null), isTrue);

      // Verify credentials are deleted
      final credential = await store.credentials.findByIdentifier(
        'user@example.com',
      );
      expect(credential, isNull);

      // Verify linked accounts are deleted
      final accounts = await store.accounts.listForUser('u1');
      expect(accounts, isEmpty);
    });
  });

  group('Account linking', () {
    late InMemoryAuthStore store;

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'user@example.com');
    });

    test('listLinkedAccounts returns linked accounts', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );

      final accounts = await listLinkedAccounts(
        store: store,
        providers: [],
        userId: 'u1',
      );
      expect(accounts, hasLength(1));
      expect(accounts.first.providerId, equals('github'));
    });

    test('unlinkProviderAccount removes the link', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );

      final unlinked = await unlinkProviderAccount(
        store: store,
        userId: 'u1',
        providerId: 'github',
        providerAccountId: 'gh-123',
      );
      expect(unlinked.providerId, equals('github'));

      // Verify the link is gone
      final found = await store.accounts.find('github', 'gh-123');
      expect(found, isNull);
    });

    test('unlinkProviderAccount fails for non-existent link', () async {
      expect(
        () => unlinkProviderAccount(
          store: store,
          userId: 'u1',
          providerId: 'github',
          providerAccountId: 'gh-999',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'linked_account_not_found',
          ),
        ),
      );
    });

    test('unlinkProviderAccount fails for wrong user', () async {
      await _seedUser(store, 'u2', 'other@example.com');
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );

      expect(
        () => unlinkProviderAccount(
          store: store,
          userId: 'u2',
          providerId: 'github',
          providerAccountId: 'gh-123',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.code,
            'code',
            'linked_account_not_found',
          ),
        ),
      );
    });

    test('account can be relinked after unlinking', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );

      await unlinkProviderAccount(
        store: store,
        userId: 'u1',
        providerId: 'github',
        providerAccountId: 'gh-123',
      );

      // Should be able to link again
      final found = await store.accounts.find('github', 'gh-123');
      expect(found, isNull);

      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-123',
          userId: 'u1',
        ),
      );
      final relinked = await store.accounts.find('github', 'gh-123');
      expect(relinked?.userId, equals('u1'));
    });

    test('canUnlinkProvider returns true when user has password', () async {
      // _seedUser already creates a credential for u1, so canUnlink should
      // return true because the user has a password credential.
      final canUnlink = await canUnlinkProvider(
        store: store,
        userId: 'u1',
        providerId: 'github',
      );
      expect(canUnlink, isTrue);
    });
  });

  group('Admin state management', () {
    late InMemoryAuthStore core;
    late InMemoryAuthAdminStore adminStore;
    late AdminPlugin<Object> feature;

    setUp(() async {
      core = InMemoryAuthStore();
      adminStore = InMemoryAuthAdminStore(core);
      await _seedUser(core, 'admin-1', 'admin@example.com', roles: ['admin']);
      await _seedUser(core, 'user-1', 'user@example.com');
      feature = AdminPlugin<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: const _Hasher(),
          plugins: [feature],
        ),
      );
    });

    test('disableUser persists disabled state', () async {
      final result = await adminStore.disableUser('user-1', reason: 'spam');
      expect(result.state.disabled, isTrue);
      expect(result.state.disabledReason, equals('spam'));

      // Verify it persists on lookup
      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.disabled, isTrue);
    });

    test('enableUser clears disabled state', () async {
      await adminStore.disableUser('user-1');
      final enabled = await adminStore.enableUser('user-1');
      expect(enabled.state.disabled, isFalse);

      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.disabled, isFalse);
    });

    test('verifyEmail sets emailVerified', () async {
      final result = await adminStore.verifyEmail('user-1');
      expect(result.state.emailVerified, isTrue);

      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.emailVerified, isTrue);
    });

    test('unlockUser clears lockout', () async {
      final unlocked = await adminStore.unlockUser('user-1');
      expect(unlocked.state.isLocked(), isFalse);
      expect(unlocked.state.failedLoginAttempts, equals(0));
    });

    test('getAccountState returns current state', () async {
      final endpoint = feature.endpoints.firstWhere(
        (e) => e.id == 'admin.getAccountState',
      );
      final result = await endpoint.invoke(
        AuthOperationInvocation<Object>(
          context: Object(),
          user: AuthUser(id: 'admin-1', roles: ['admin']),
        ),
        {'userId': 'user-1'},
      );
      final state = result as Map<String, dynamic>;
      expect(state['userId'], equals('user-1'));
      expect(state['disabled'], isFalse);
    });

    test('getAccountState reports authentication lockout counters', () async {
      await core.recordFailedLogin(
        'user-1',
        policy: const AuthAccountPolicy(maxLoginAttempts: 1),
      );
      final endpoint = feature.endpoints.firstWhere(
        (value) => value.id == 'admin.getAccountState',
      );
      final result = await endpoint.invoke(
        AuthOperationInvocation<Object>(
          context: Object(),
          user: AuthUser(id: 'admin-1', roles: ['admin']),
        ),
        {'userId': 'user-1'},
      );
      final state = result as Map<String, dynamic>;
      expect(state['failedLoginAttempts'], equals(1));
      expect(state['lockedUntil'], isNotNull);
    });
  });

  group('Browser protection', () {
    test('AuthBrowserProtectionOptions defaults', () {
      const opts = AuthBrowserProtectionOptions();
      expect(opts.enabled, isTrue);
      expect(opts.allowedOrigins, isEmpty);
      expect(opts.trustedOrigins, isEmpty);
      expect(opts.requireOrigin, isFalse);
      expect(opts.enforceFetchMetadata, isTrue);
      expect(opts.enforceReferrer, isFalse);
    });

    test('copyWith preserves values', () {
      const opts = AuthBrowserProtectionOptions();
      final copied = opts.copyWith(
        enabled: false,
        trustedOrigins: ['https://example.com'],
      );
      expect(copied.enabled, isFalse);
      expect(copied.trustedOrigins, equals(['https://example.com']));
      expect(copied.enforceFetchMetadata, isTrue); // preserved
    });

    test('AuthCookiePolicy defaults', () {
      const policy = AuthCookiePolicy();
      expect(policy.httpOnly, isTrue);
      expect(policy.secure, isTrue);
      expect(policy.path, equals('/'));
    });

    test('AuthCookiePolicy.copyWith preserves values', () {
      const policy = AuthCookiePolicy();
      final copied = policy.copyWith(httpOnly: false);
      expect(copied.httpOnly, isFalse);
      expect(copied.secure, isTrue); // preserved
      expect(copied.path, equals('/')); // preserved
    });

    test('AuthBrowserProtectionValidator rejects bad origin when enabled', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(
          enabled: true,
          requireOrigin: true,
        ),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://app.example.com/auth/signin'),
        headers: _MockHeaders({'origin': 'https://evil.com'}),
        method: 'POST',
      );
      expect(result.isValid, isFalse);
      expect(result.errorCode, equals('invalid_origin'));
    });

    test('AuthBrowserProtectionValidator accepts same-origin', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(
          enabled: true,
          requireOrigin: true,
        ),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://app.example.com/auth/signin'),
        headers: _MockHeaders({'origin': 'https://app.example.com'}),
        method: 'POST',
      );
      expect(result.isValid, isTrue);
    });

    test('AuthBrowserProtectionValidator accepts trusted origin', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(
          enabled: true,
          requireOrigin: true,
          trustedOrigins: ['https://trusted.example.com'],
        ),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://app.example.com/auth/signin'),
        headers: _MockHeaders({'origin': 'https://trusted.example.com'}),
        method: 'POST',
      );
      expect(result.isValid, isTrue);
    });

    test('rejects cross-site metadata without an allowed origin', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(enabled: true),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://app.example.com/auth/signin'),
        headers: _MockHeaders({'sec-fetch-site': 'cross-site'}),
        method: 'POST',
      );
      expect(result.isValid, isFalse);
      expect(result.errorCode, equals('cross_site_request'));
    });

    test('accepts cross-site metadata only with an allowed origin', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(
          enabled: true,
          allowedOrigins: ['https://frontend.example.com'],
        ),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://api.example.com/auth/signin'),
        headers: _MockHeaders({
          'origin': 'https://frontend.example.com',
          'sec-fetch-site': 'cross-site',
        }),
        method: 'POST',
      );
      expect(result.isValid, isTrue);
    });

    test('rejects methods outside the configured allowlist', () {
      final validator = AuthBrowserProtectionValidator(
        options: const AuthBrowserProtectionOptions(
          enabled: true,
          allowedMethods: {'GET', 'POST'},
        ),
      );
      final result = validator.validate(
        requestUri: Uri.parse('https://app.example.com/auth/signin'),
        headers: _MockHeaders({'origin': 'https://app.example.com'}),
        method: 'DELETE',
      );
      expect(result.isValid, isFalse);
      expect(result.errorCode, equals('method_not_allowed'));
    });

    test(
      'content-type validation rejects when requireContentType is enabled',
      () {
        final validator = AuthBrowserProtectionValidator(
          options: const AuthBrowserProtectionOptions(
            enabled: true,
            requireContentType: true,
          ),
        );
        final result = validator.validate(
          requestUri: Uri.parse('https://app.example.com/auth/signin'),
          headers: _MockHeaders({'origin': 'https://app.example.com'}),
          method: 'POST',
        );
        // Empty content type should be rejected when required
        expect(result.isValid, isFalse);
        expect(result.errorCode, equals('missing_content_type'));
      },
    );

    test(
      'content-type validation accepts when requireContentType is disabled',
      () {
        final validator = AuthBrowserProtectionValidator(
          options: const AuthBrowserProtectionOptions(
            enabled: true,
            requireContentType: false,
          ),
        );
        final result = validator.validate(
          requestUri: Uri.parse('https://app.example.com/auth/signin'),
          headers: _MockHeaders({'origin': 'https://app.example.com'}),
          method: 'POST',
        );
        expect(result.isValid, isTrue);
      },
    );
  });

  group('OAuth provider mode', () {
    late InMemoryOAuthClientStore clientStore;
    late InMemoryOAuthAuthorizationCodeStore codeStore;
    late InMemoryOAuthAccessTokenStore tokenStore;

    setUp(() {
      clientStore = InMemoryOAuthClientStore();
      codeStore = InMemoryOAuthAuthorizationCodeStore();
      tokenStore = InMemoryOAuthAccessTokenStore();
    });

    test('OAuthClient serialization roundtrip', () async {
      final now = DateTime.now().toUtc();
      final client = OAuthClient(
        clientId: 'c1',
        clientSecretHash: 'hash',
        name: 'Test Client',
        redirectUris: ['https://example.com/callback'],
        createdAt: now,
        updatedAt: now,
      );
      await clientStore.create(client);
      final found = await clientStore.findById('c1');
      expect(found, isNotNull);
      expect(found!.name, equals('Test Client'));
      expect(found.redirectUris, equals(['https://example.com/callback']));
    });

    test('OAuthClient grant types are preserved', () async {
      final client = OAuthClient(
        clientId: 'c1',
        clientSecretHash: 'hash',
        name: 'Test',
        redirectUris: ['https://example.com/callback'],
        grantTypes: const ['authorization_code'],
      );
      await clientStore.create(client);
      final found = await clientStore.findById('c1');
      expect(found?.grantTypes, equals(['authorization_code']));
    });

    test('OAuthAccessTokenStore findByRefreshToken', () async {
      final token = OAuthAccessToken(
        token: 'access-123',
        clientId: 'c1',
        userId: 'u1',
        scope: 'openid',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        refreshToken: 'refresh-456',
        issuedAt: DateTime.now().toUtc(),
      );
      await tokenStore.save(token);

      final found = await tokenStore.findByRefreshToken('refresh-456');
      expect(found, isNotNull);
      expect(found!.token, equals('access-123'));

      final notFound = await tokenStore.findByRefreshToken('bad-refresh');
      expect(notFound, isNull);
    });

    test('OAuthAccessTokenStore revokes all for user', () async {
      await tokenStore.save(
        OAuthAccessToken(
          token: 't1',
          clientId: 'c1',
          userId: 'u1',
          scope: '',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          token: 't2',
          clientId: 'c1',
          userId: 'u2',
          scope: '',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final revoked = await tokenStore.revokeAllForUser('u1');
      expect(revoked, equals(1));
      expect(await tokenStore.findByToken('t1'), isNull);
      expect(await tokenStore.findByToken('t2'), isNotNull);
    });

    test('OAuthAuthorizationCodeStore consume is one-time', () async {
      final now = DateTime.now().toUtc();
      await codeStore.save(
        OAuthAuthorizationCode(
          code: 'auth-code-1',
          clientId: 'c1',
          userId: 'u1',
          redirectUri: 'https://example.com/callback',
          scope: 'openid',
          expiresAt: now.add(const Duration(minutes: 5)),
          createdAt: now,
        ),
      );

      final consumed = await codeStore.consume('auth-code-1');
      expect(consumed, isNotNull);

      // Second consume returns null
      final second = await codeStore.consume('auth-code-1');
      expect(second, isNull);
    });

    test('OAuthAuthorizationCodeStore rejects expired codes', () async {
      final now = DateTime.now().toUtc();
      await codeStore.save(
        OAuthAuthorizationCode(
          code: 'expired-code',
          clientId: 'c1',
          userId: 'u1',
          redirectUri: 'https://example.com/callback',
          scope: 'openid',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          createdAt: now,
        ),
      );

      final consumed = await codeStore.consume('expired-code');
      expect(consumed, isNull);
    });

    test('OAuthProviderModeOptions defaults', () {
      const opts = OAuthProviderModeOptions();
      expect(opts.codeLifetime, equals(const Duration(minutes: 10)));
      expect(opts.accessTokenLifetime, equals(const Duration(hours: 1)));
      expect(opts.requirePkce, isTrue);
      expect(opts.allowRefreshTokenRotation, isTrue);
    });
  });

  group('OAuth account store', () {
    late InMemoryAuthStore store;

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'user@example.com');
    });

    test('listForUser returns linked accounts', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-1',
          userId: 'u1',
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'google',
          providerAccountId: 'goog-1',
          userId: 'u1',
        ),
      );

      final accounts = await store.accounts.listForUser('u1');
      expect(accounts, hasLength(2));
    });

    test('listForUser returns empty for unknown user', () async {
      final accounts = await store.accounts.listForUser('unknown');
      expect(accounts, isEmpty);
    });

    test('deleteForUser removes all accounts for user', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-1',
          userId: 'u1',
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'google',
          providerAccountId: 'goog-1',
          userId: 'u1',
        ),
      );

      await store.accounts.deleteForUser('u1');
      final accounts = await store.accounts.listForUser('u1');
      expect(accounts, isEmpty);
    });

    test('unlink removes the record entirely', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'gh-1',
          userId: 'u1',
        ),
      );

      final unlinked = await store.accounts.unlinkForUser(
        'u1',
        'github',
        'gh-1',
      );
      expect(unlinked, isTrue);

      // Record should be gone, not just nullified
      final found = await store.accounts.find('github', 'gh-1');
      expect(found, isNull);
    });
  });

  group('Credential store deleteForUser', () {
    late InMemoryAuthStore store;

    setUp(() async {
      store = InMemoryAuthStore();
    });

    test('deleteForUser removes all credentials for user', () async {
      // _seedUser creates the user and credential atomically
      await _seedUser(store, 'u1', 'user@example.com');

      expect(
        await store.credentials.findByIdentifier('user@example.com'),
        isNotNull,
      );

      await store.credentials.deleteForUser('u1');

      expect(
        await store.credentials.findByIdentifier('user@example.com'),
        isNull,
      );
    });
  });

  group('User store delete', () {
    late InMemoryAuthStore store;

    setUp(() async {
      store = InMemoryAuthStore();
    });

    test('delete removes user by ID', () async {
      await store.users.create(AuthUser(id: 'u1', email: 'user@example.com'));
      expect(await store.users.findById('u1'), isNotNull);

      final deleted = await store.users.delete('u1');
      expect(deleted, isTrue);
      expect(await store.users.findById('u1'), isNull);
      expect(await store.users.findByEmail('user@example.com'), isNull);
    });

    test('delete returns false for unknown user', () async {
      final deleted = await store.users.delete('unknown');
      expect(deleted, isFalse);
    });

    test('delete returns false for empty ID', () async {
      final deleted = await store.users.delete('');
      expect(deleted, isFalse);
    });
  });
}

// --- Helpers ---

Future<void> _seedUser(
  InMemoryAuthStore store,
  String id,
  String email, {
  List<String> roles = const ['user'],
}) async {
  // Use the credential store's atomic register which also creates the user.
  // If the user already exists, register silently returns null, so skip.
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
  // If register returned null (user already existed), ensure the user exists.
  if (result == null) {
    await store.users.create(user);
  }
}

class _Hasher implements PasswordHasher {
  const _Hasher();

  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) {
    final matches = encodedHash == 'hash:$password';
    return PasswordVerification(matches: matches, needsRehash: false);
  }
}

class _MockHeaders implements HttpHeaders {
  final Map<String, String> _headers;
  _MockHeaders(this._headers);

  @override
  String? value(String name) => _headers[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
