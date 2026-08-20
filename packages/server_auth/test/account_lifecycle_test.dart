import 'dart:async';
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
      store.bindUserDeletionPlanContributors(const []);
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

    test('confirmed deletion clears account policy state', () async {
      await store.upsert(
        const AuthAccountState(
          userId: 'u1',
          disabled: true,
          failedLoginAttempts: 4,
        ),
      );
      await store.verificationTokens.save(
        AuthVerificationToken(
          identifier: 'account_deletion:u1',
          token: 'delete-token',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final deleted = await store.userDeletionCoordinator.confirmAndDeleteUser(
        userId: 'u1',
        token: 'delete-token',
      );

      expect(deleted, isTrue);
      expect(await store.find('u1'), isNull);
    });

    test(
      'administrative deletion and purge clear account policy state',
      () async {
        await store.upsert(
          const AuthAccountState(userId: 'u1', disabled: true),
        );
        expect(await store.deleteUserForAdministration('u1'), isTrue);
        expect(await store.find('u1'), isNull);

        await _seedUser(store, 'u2', 'two@example.com');
        await store.upsert(
          const AuthAccountState(userId: 'u2', failedLoginAttempts: 3),
        );
        expect(await store.tombstoneUserForAdministration('u2'), isTrue);
        expect(await store.find('u2'), isNotNull);
        expect(await store.purgeTombstonedUserForAdministration('u2'), isTrue);
        expect(await store.find('u2'), isNull);
      },
    );
  });

  group('Account linking', () {
    late InMemoryAuthStore store;
    late AuthAuthenticationMethodService authenticationMethods;

    setUp(() async {
      store = InMemoryAuthStore();
      await _seedUser(store, 'u1', 'user@example.com');
      authenticationMethods = _authenticationMethods(store);
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
        authenticationMethods: authenticationMethods,
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
          authenticationMethods: authenticationMethods,
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
          authenticationMethods: authenticationMethods,
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
        authenticationMethods: authenticationMethods,
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

    test(
      'concurrent links report only the canonical owner as successful',
      () async {
        final bothLookedUp = Completer<void>();
        var lookupCount = 0;
        AuthAccount? canonical;
        final concurrentStore = CallbackAuthStore(
          onFindUserById: (id) => AuthUser(id: id),
          onFindAccount: (_, _) async {
            lookupCount += 1;
            if (lookupCount == 2) bothLookedUp.complete();
            await bothLookedUp.future;
            return null;
          },
          onLinkAccount: (account) => canonical ??= account,
        );

        Future<Object> attempt(String userId) async {
          try {
            return await linkProviderAccount(
              store: concurrentStore,
              userId: userId,
              providerId: 'github',
              providerAccountId: 'shared-account',
            );
          } catch (error) {
            return error;
          }
        }

        final results = await Future.wait([attempt('u1'), attempt('u2')]);
        expect(results.whereType<AuthAccountLinked>(), hasLength(1));
        expect(
          results.whereType<AuthFlowException>().single.code,
          'provider_account_already_linked',
        );
        expect(
          (results.whereType<AuthAccountLinked>().single).isNewLink,
          isTrue,
        );
      },
    );

    test(
      'concurrent unlinks preserve one provider authentication method',
      () async {
        final oauthOnlyStore = InMemoryAuthStore();
        final oauthMethods = _authenticationMethods(
          oauthOnlyStore,
          includeCredentials: false,
        );
        await oauthOnlyStore.users.create(AuthUser(id: 'oauth-user'));
        await oauthOnlyStore.accounts.link(
          AuthAccount(
            providerId: 'github',
            providerAccountId: 'github-account',
            userId: 'oauth-user',
          ),
        );
        await oauthOnlyStore.accounts.link(
          AuthAccount(
            providerId: 'google',
            providerAccountId: 'google-account',
            userId: 'oauth-user',
          ),
        );

        Future<Object> attempt(String provider, String accountId) async {
          try {
            return await unlinkProviderAccount(
              store: oauthOnlyStore,
              authenticationMethods: oauthMethods,
              userId: 'oauth-user',
              providerId: provider,
              providerAccountId: accountId,
            );
          } catch (error) {
            return error;
          }
        }

        final results = await Future.wait([
          attempt('github', 'github-account'),
          attempt('google', 'google-account'),
        ]);
        expect(results.whereType<AuthAccountUnlinked>(), hasLength(1));
        expect(
          results.whereType<AuthFlowException>().single.code,
          'last_authentication_method',
        );
        expect(
          await oauthOnlyStore.accounts.listForUser('oauth-user'),
          hasLength(1),
        );
      },
    );

    test('canUnlinkProvider returns true when user has password', () async {
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: 'u1',
        ),
      );
      // _seedUser already creates a credential for u1, so canUnlink should
      // return true because the user has a password credential.
      final canUnlink = await canUnlinkProvider(
        store: store,
        authenticationMethods: authenticationMethods,
        userId: 'u1',
        providerId: 'github',
        providerAccountId: 'github-1',
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
      final result = await adminStore.execute(
        AuthAdminSetAccountStateMutation(
          authorization: _adminMutationAuthorization('ban'),
          userId: 'user-1',
          action: AuthAdminAccountStateAction.disable,
          reason: 'spam',
        ),
      );
      expect(result.state.disabled, isTrue);
      expect(result.state.disabledReason, equals('spam'));

      // Verify it persists on lookup
      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.disabled, isTrue);
    });

    test('enableUser clears disabled state', () async {
      await adminStore.execute(
        AuthAdminSetAccountStateMutation(
          authorization: _adminMutationAuthorization('ban'),
          userId: 'user-1',
          action: AuthAdminAccountStateAction.disable,
        ),
      );
      final enabled = await adminStore.execute(
        AuthAdminSetAccountStateMutation(
          authorization: _adminMutationAuthorization('ban'),
          userId: 'user-1',
          action: AuthAdminAccountStateAction.enable,
        ),
      );
      expect(enabled.state.disabled, isFalse);

      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.disabled, isFalse);
    });

    test('verifyEmail sets emailVerified', () async {
      final result = await adminStore.execute(
        AuthAdminSetAccountStateMutation(
          authorization: _adminMutationAuthorization('update'),
          userId: 'user-1',
          action: AuthAdminAccountStateAction.verifyEmail,
        ),
      );
      expect(result.state.emailVerified, isTrue);

      final lookedUp = await adminStore.findUser('user-1');
      expect(lookedUp?.state.emailVerified, isTrue);
    });

    test('unlockUser clears lockout', () async {
      final unlocked = await adminStore.execute(
        AuthAdminSetAccountStateMutation(
          authorization: _adminMutationAuthorization('ban'),
          userId: 'user-1',
          action: AuthAdminAccountStateAction.unlock,
        ),
      );
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
        tokenHash: hashOpaqueToken('access-123'),
        clientId: 'c1',
        userId: 'u1',
        scope: 'openid',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        refreshTokenHash: hashOpaqueToken('refresh-456'),
        issuedAt: DateTime.now().toUtc(),
      );
      await tokenStore.save(token);

      expect(token.tokenHash, isNot('access-123'));
      expect(token.refreshTokenHash, isNot('refresh-456'));

      final found = await tokenStore.findByRefreshToken('refresh-456');
      expect(found, isNotNull);
      expect(found!.tokenHash, equals(hashOpaqueToken('access-123')));

      final notFound = await tokenStore.findByRefreshToken('bad-refresh');
      expect(notFound, isNull);
    });

    test('OAuthAccessTokenStore revokes all for user', () async {
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('t1'),
          clientId: 'c1',
          userId: 'u1',
          scope: '',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('t2'),
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
      await codeStore.create(
        OAuthAuthorizationCode(
          authorizationId: 'authorization-1',
          codeHash: hashOpaqueToken('auth-code-1'),
          clientId: 'c1',
          userId: 'u1',
          redirectUri: 'https://example.com/callback',
          scope: 'openid',
          expiresAt: now.add(const Duration(minutes: 5)),
          createdAt: now,
        ),
      );

      final consumed = await codeStore.consume(
        codeHash: hashOpaqueToken('auth-code-1'),
        clientId: 'c1',
        redirectUri: 'https://example.com/callback',
        codeVerifier: null,
      );
      expect(consumed, isNotNull);

      // Second consume returns null
      final second = await codeStore.consume(
        codeHash: hashOpaqueToken('auth-code-1'),
        clientId: 'c1',
        redirectUri: 'https://example.com/callback',
        codeVerifier: null,
      );
      expect(second, isNull);
    });

    test('OAuthAuthorizationCodeStore rejects expired codes', () async {
      final now = DateTime.now().toUtc();
      await codeStore.create(
        OAuthAuthorizationCode(
          authorizationId: 'authorization-expired',
          codeHash: hashOpaqueToken('expired-code'),
          clientId: 'c1',
          userId: 'u1',
          redirectUri: 'https://example.com/callback',
          scope: 'openid',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
      );

      final consumed = await codeStore.consume(
        codeHash: hashOpaqueToken('expired-code'),
        clientId: 'c1',
        redirectUri: 'https://example.com/callback',
        codeVerifier: null,
      );
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

AuthAdminMutationAuthorization _adminMutationAuthorization(String action) =>
    AuthAdminMutationAuthorization(
      actorId: 'admin-1',
      administratorRoles: const <String>{'admin'},
      administratorUserIds: const <String>{},
      rolePermissions: const <String, AuthAdminPermissionSet>{
        'admin': <String, Iterable<String>>{
          'user': <String>['update', 'ban'],
        },
      },
      requirements: <AuthAdminPermissionRequirement>[
        AuthAdminPermissionRequirement('user', action),
      ],
    );

AuthAuthenticationMethodService _authenticationMethods(
  InMemoryAuthStore store, {
  bool includeCredentials = true,
}) => AuthRuntime<Object>(
  options: AuthOptions<Object>(
    providers: <AuthProvider>[
      if (includeCredentials) CredentialsProvider(),
      for (final id in const ['github', 'google'])
        OAuthProvider<Map<String, dynamic>>(
          id: id,
          name: id,
          clientId: 'client',
          clientSecret: 'secret',
          authorizationEndpoint: Uri.https('$id.test', '/authorize'),
          tokenEndpoint: Uri.https('$id.test', '/token'),
          profile: (_) => AuthUser(id: 'unused'),
          redirectUri: 'https://app.test/auth/callback/$id',
        ),
    ],
    store: store,
    storeMode: AuthStoreMode.ephemeral,
  ),
).authenticationMethods;

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
