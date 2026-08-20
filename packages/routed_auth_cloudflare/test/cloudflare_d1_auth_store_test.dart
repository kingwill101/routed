import 'dart:convert';

import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('CloudflareD1UserDeletionStatement', () {
    test('rejects local placeholders after the coordinator guard', () {
      expect(
        () => CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM records WHERE {{guard}} AND user_id = ?',
          parameters: const ['user-1'],
        ),
        throwsArgumentError,
      );
    });
  });

  group('CloudflareD1AuthStore conformance', () {
    final suite = AuthStoreConformanceSuite(
      createFixture: () async {
        final database = FakeCloudflareD1Database();
        final store = await CloudflareD1AuthStore.open(database);
        return AuthStoreConformanceFixture(
          store: store,
          dispose: database.close,
        );
      },
    );

    for (final conformanceCase in suite.cases) {
      test(conformanceCase.description, () async {
        final result = await conformanceCase.run();
        expect(result.isSkipped, isFalse, reason: result.skippedReason);
      });
    }
  });

  test('D1 rejects the in-memory OAuth provider exchange topology', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);
    final provider = OAuthProviderModePlugin<Object>(
      clientStore: InMemoryOAuthClientStore(),
      authorizationCodeExchangeStore:
          InMemoryOAuthAuthorizationCodeExchangeStore(),
    );

    expect(
      () => provider.configure(AuthServerPluginContext<Object>(store: store)),
      throwsStateError,
    );
  });

  test('D1 username store satisfies public atomic conformance', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);

    await verifyAuthUsernameStoreConformance(
      AuthUsernameStoreConformanceFixture(
        store: store,
        armFault: (point) =>
            database.failNextBatchAfterStatements(switch (point) {
              AuthUsernameFaultPoint.registrationAfterUserWrite => 2,
              AuthUsernameFaultPoint.changeAfterCredentialWrite => 2,
              AuthUsernameFaultPoint.changeAfterUserWrite => 3,
              AuthUsernameFaultPoint.removalAfterUserWrite => 2,
              AuthUsernameFaultPoint.removalAfterCredentialWrite => 3,
            }),
      ),
    );
    expect(
      database.select(
        'SELECT operation_key FROM routed_auth_username_mutation_guards',
      ),
      isEmpty,
    );

    store.bindUserDeletionPlanContributors(const []);
    final now = DateTime.utc(2030);
    final user = AuthUser(
      id: 'd1-username-delete-user',
      attributes: const <String, dynamic>{'username': 'd1-username-delete'},
    );
    final deletedRegistration = await store.registerUsername(
      AuthUsernameRegistrationCommand(
        user: user,
        credential: AuthPasswordCredential(
          id: 'd1-username-delete-credential',
          userId: user.id,
          identifier: 'd1-username-delete',
          passwordHash: 'encoded-hash',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    expect(deletedRegistration.succeeded, isTrue);
    expect(await store.userDeletionCoordinator.deleteUser(user.id), isTrue);
    expect(await store.findByUsername('d1-username-delete'), isNull);
  });

  test('D1 unlink excludes the exact provider and account pair', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);
    final service = _accountMethodService(store, {'github', 'gitlab'});
    await store.users.create(AuthUser(id: 'user-1'));
    await store.accounts.link(
      AuthAccount(
        providerId: 'github',
        providerAccountId: 'shared-id',
        userId: 'user-1',
      ),
    );
    await store.accounts.link(
      AuthAccount(
        providerId: 'gitlab',
        providerAccountId: 'shared-id',
        userId: 'user-1',
      ),
    );

    final result = await service.removeOAuthAccountIfSafe(
      userId: 'user-1',
      providerId: 'github',
      providerAccountId: 'shared-id',
    );

    expect(result, AuthAuthenticationMethodMutationResult.mutated);
    expect(await store.accounts.find('github', 'shared-id'), isNull);
    expect(await store.accounts.find('gitlab', 'shared-id'), isNotNull);
  });

  test('D1 unlink recognizes a durable password fallback', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: <AuthProvider>[
          CredentialsProvider(),
          _oauthProvider('github'),
        ],
        store: store,
        runtimeMode: AuthRuntimeMode.localDevelopment,
      ),
    );
    final now = DateTime.utc(2026, 8, 20);
    await store.credentials.register(
      AuthUser(id: 'user-1', email: 'user@example.com'),
      AuthPasswordCredential(
        id: 'credential-1',
        userId: 'user-1',
        identifier: 'user@example.com',
        passwordHash: 'hash',
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

    final result = await runtime.authenticationMethods.removeOAuthAccountIfSafe(
      userId: 'user-1',
      providerId: 'github',
      providerAccountId: 'github-1',
    );

    expect(result, AuthAuthenticationMethodMutationResult.mutated);
    expect(await store.accounts.find('github', 'github-1'), isNull);
  });

  test('concurrent D1 unlinks preserve one usable account', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);
    final providers = {'github', 'gitlab', 'bitbucket'};
    final service = _accountMethodService(store, providers);
    await store.users.create(AuthUser(id: 'user-1'));
    for (final providerId in providers) {
      await store.accounts.link(
        AuthAccount(
          providerId: providerId,
          providerAccountId: '$providerId-account',
          userId: 'user-1',
        ),
      );
    }

    final results = await Future.wait([
      for (final providerId in providers)
        service.removeOAuthAccountIfSafe(
          userId: 'user-1',
          providerId: providerId,
          providerAccountId: '$providerId-account',
        ),
    ]);

    final remaining = await store.accounts.listForUser('user-1');
    expect(remaining, hasLength(1));
    expect(
      results.where(
        (result) => result == AuthAuthenticationMethodMutationResult.mutated,
      ),
      hasLength(2),
    );
    expect(
      results,
      contains(AuthAuthenticationMethodMutationResult.lastAuthenticationMethod),
    );
  });

  test(
    'D1 records external method stores and makes unlink unavailable',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(database);
      final service = AuthAuthenticationMethodService(
        store: store,
        contributors: [
          _D1AccountMethodInventory(store.accounts, {'github', 'gitlab'}),
          _ExternalMethodInventory(),
        ],
      )..composeContributors(const []);
      await store.users.create(AuthUser(id: 'user-1'));
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: 'user-1',
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'gitlab',
          providerAccountId: 'gitlab-1',
          userId: 'user-1',
        ),
      );

      final result = await service.removeOAuthAccountIfSafe(
        userId: 'user-1',
        providerId: 'github',
        providerAccountId: 'github-1',
      );

      expect(
        result,
        AuthAuthenticationMethodMutationResult.atomicityUnavailable,
      );
      expect(await store.accounts.listForUser('user-1'), hasLength(2));
    },
  );

  test(
    'D1 boots with external auth plugins while unlink fails closed',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(database);
      final webAuthnStorage = InMemoryAuthStore();
      final phoneStore = InMemoryAuthPhoneNumberStore();
      final apiKeyStore = InMemoryAuthApiKeyStore();
      final webAuthn = WebAuthnPlugin<Object>(
        provider: WebAuthnProvider(
          getUserInfo: (_, _, _) => null,
          getRelyingParty: (_, _) => const WebAuthnRelyingParty(
            id: 'app.test',
            name: 'App',
            origin: 'https://app.test',
          ),
        ),
        storage: webAuthnStorage,
      );
      final phone = PhoneNumberPlugin<Object>(
        store: phoneStore,
        sendCode: (_) {},
        codeHashKey: '0123456789abcdef0123456789abcdef',
        allowSignUp: true,
        generateCode: (_) => '123456',
      );
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: apiKeyStore,
        countsAsPrimaryAuthenticationMethod: true,
        keyIdGenerator: ({int length = 32}) => 'key-id',
        secretGenerator: ({int length = 32}) => 'key-secret',
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: <AuthProvider>[
            _oauthProvider('github'),
            _oauthProvider('gitlab'),
          ],
          store: store,
          runtimeMode: AuthRuntimeMode.localDevelopment,
          plugins: <AuthServerPlugin<Object>>[webAuthn, phone, apiKeys],
        ),
      );
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      await webAuthnStorage.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: 'passkey-1',
          publicKey: 'AQ',
          counter: 0,
          userId: user.id,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      );
      final options = await webAuthn.beginUserBoundAuthentication(
        context: Object(),
        user: user,
      );
      expect(options.challenge, isNotEmpty);

      await phone.issueCode(context: Object(), phoneNumber: '+18765551234');
      final phoneAuthentication = await phone.verifyCode(
        context: Object(),
        phoneNumber: '+18765551234',
        code: '123456',
      );
      expect(phoneAuthentication.user.id, isNotEmpty);

      final issued = await apiKeys.issue(userId: user.id, name: 'primary');
      expect((await apiKeys.authenticate(issued.key))?.record.userId, user.id);

      for (final providerId in ['github', 'gitlab']) {
        await store.accounts.link(
          AuthAccount(
            providerId: providerId,
            providerAccountId: '$providerId-account',
            userId: user.id,
          ),
        );
      }
      final unlink = await runtime.authenticationMethods
          .removeOAuthAccountIfSafe(
            userId: user.id,
            providerId: 'github',
            providerAccountId: 'github-account',
          );
      expect(
        unlink,
        AuthAuthenticationMethodMutationResult.atomicityUnavailable,
      );
      expect(await store.accounts.listForUser(user.id), hasLength(2));
    },
  );

  test('typed migrations are idempotent and prefixes are isolated', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    const first = CloudflareD1AuthSchema(tablePrefix: 'auth_one');
    const second = CloudflareD1AuthSchema(tablePrefix: 'auth_two');

    await first.migrate(database);
    await first.migrate(database);
    await second.migrate(database);

    final firstStore = CloudflareD1AuthStore(database, schema: first);
    final secondStore = CloudflareD1AuthStore(database, schema: second);
    await firstStore.users.create(
      AuthUser(id: 'one', email: 'one@example.com'),
    );

    expect(await secondStore.users.findById('one'), isNull);
  });

  test('issuance-lease migration preserves existing authorizations', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    const schema = CloudflareD1AuthSchema(tablePrefix: 'auth_legacy');
    final migrationsTable = schema.table('migrations');
    await database.exec('''CREATE TABLE $migrationsTable (
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    )''');
    for (final migration in schema.migrations.take(2)) {
      await database.batch<Object?>([
        for (final statement in migration.statements)
          database.prepare(statement),
        database
            .prepare(
              'INSERT INTO $migrationsTable (version, applied_at) VALUES (?, ?)',
            )
            .bind([migration.version, DateTime.utc(2026).toIso8601String()]),
      ]);
    }
    final now = DateTime.utc(2026, 8, 20, 12);
    final authorization = AuthDeviceAuthorization(
      id: 'legacy-device',
      deviceCodeHash: 'legacy-device-hash',
      userCodeHash: 'legacy-user-hash',
      clientId: 'legacy-client',
      scopes: const ['openid'],
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      interval: const Duration(seconds: 5),
      status: AuthDeviceAuthorizationStatus.approved,
      userId: 'legacy-user',
      approvedAt: now,
    );
    await database
        .prepare('''INSERT INTO ${schema.table('device_authorizations')}
          (device_code_hash, user_code_hash, user_id, status, expires_at, payload)
          VALUES (?, ?, ?, ?, ?, ?)''')
        .bind([
          authorization.deviceCodeHash,
          authorization.userCodeHash,
          authorization.userId,
          authorization.status.name,
          authorization.expiresAt.toIso8601String(),
          jsonEncode(authorization.toStorageJson()),
        ])
        .run();

    await schema.migrate(database);
    final store = CloudflareD1AuthStore(
      database,
      schema: schema,
      clock: () => now,
    );
    final lease = await store.deviceAuthorizations.beginIssuance(
      authorization.deviceCodeHash,
      clientId: authorization.clientId,
      leaseDigest: 'migrated-lease',
      leaseExpiresAt: now.add(const Duration(seconds: 30)),
      now: now,
    );

    expect(lease.status, AuthDeviceAuthorizationIssuanceLeaseStatus.acquired);
    expect(lease.lease!.authorization.id, authorization.id);
    expect(
      database
          .select('SELECT version FROM $migrationsTable ORDER BY version')
          .map((row) => row['version']),
      [1, 2, 3, 4, 5, 6, 7, 8, 9],
    );
  });

  test('migration rejects unsafe table prefixes', () {
    const schema = CloudflareD1AuthSchema(
      tablePrefix: 'auth; DROP TABLE users',
    );
    expect(() => schema.table('users'), throwsArgumentError);
    expect(
      () => const CloudflareD1AuthSchema().table('users; DROP TABLE users'),
      throwsArgumentError,
    );
  });

  test('exposes a backend-bound deletion coordinator', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);

    expect(store, isA<AuthUserDeletionCoordinatorHost>());
    expect(
      store.userDeletionCoordinator.domain,
      isA<CloudflareD1UserDeletionDomain>(),
    );
  });

  test('D1 deletion rolls back faults and retries the same token', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 20, 12);
    final store = await CloudflareD1AuthStore.open(database, clock: () => now);
    final coordinator = store.userDeletionCoordinator;
    final domain = coordinator.domain as CloudflareD1UserDeletionDomain;
    await database.exec(
      'CREATE TABLE plugin_data (user_id TEXT PRIMARY KEY, value TEXT)',
    );
    await store.users.create(AuthUser(id: 'delete-me'));
    await database
        .prepare('INSERT INTO plugin_data (user_id, value) VALUES (?, ?)')
        .bind(['delete-me', 'retained-on-fault'])
        .run();
    await store.verificationTokens.save(
      AuthVerificationToken(
        identifier: 'account_deletion:delete-me',
        token: 'delete-token',
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    store.bindUserDeletionPlanContributors([
      _D1DeletionContributor(domain: domain, injectFaultOnce: true),
    ]);

    await expectLater(
      coordinator.confirmAndDeleteUser(
        userId: 'delete-me',
        token: 'delete-token',
        now: now,
      ),
      throwsA(anything),
    );
    expect(await store.users.findById('delete-me'), isNotNull);
    expect(database.select('SELECT * FROM plugin_data'), hasLength(1));
    expect(
      database.select(
        'SELECT * FROM ${store.schema.table('deletion_receipts')}',
      ),
      isEmpty,
    );

    final results = await Future.wait([
      coordinator.confirmAndDeleteUser(
        userId: 'delete-me',
        token: 'delete-token',
        now: now,
      ),
      coordinator.confirmAndDeleteUser(
        userId: 'delete-me',
        token: 'delete-token',
        now: now,
      ),
    ]);
    expect(results.where((value) => value), hasLength(1));
    expect(await store.users.findById('delete-me'), isNull);
    expect(database.select('SELECT * FROM plugin_data'), isEmpty);
    expect(
      database.select(
        'SELECT * FROM ${store.schema.table('deletion_receipts')}',
      ),
      hasLength(1),
    );
    await expectLater(
      store.users.create(AuthUser(id: 'delete-me')),
      throwsStateError,
    );
  });

  test('D1 rejects a foreign deletion domain before mutation', () async {
    final firstDatabase = FakeCloudflareD1Database();
    final secondDatabase = FakeCloudflareD1Database();
    addTearDown(firstDatabase.close);
    addTearDown(secondDatabase.close);
    final first = await CloudflareD1AuthStore.open(firstDatabase);
    final second = await CloudflareD1AuthStore.open(secondDatabase);
    first.bindUserDeletionPlanContributors(const []);
    await first.users.create(AuthUser(id: 'user-1'));
    final foreign = CloudflareD1UserDeletionPlan(
      domain:
          second.userDeletionCoordinator.domain
              as CloudflareD1UserDeletionDomain,
      userId: 'user-1',
      namespace: 'foreign',
      statements: const [],
    );

    await expectLater(
      first.userDeletionCoordinator.deleteUser('user-1', plans: [foreign]),
      throwsA(isA<AuthUserDeletionPreflightException>()),
    );
    expect(await first.users.findById('user-1'), isNotNull);
  });

  test('D1 plugin plans delete device and email OTP namespaces', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 20, 12);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(
      database,
      schema: schema,
      clock: () => now,
    );
    final user = AuthUser(id: 'user-1', email: 'user@example.com');
    await store.users.create(user);
    final device = DeviceAuthorizationPlugin<Object>(
      verificationUri: 'https://auth.example.com/device',
      validateClient: (_, _, _) => true,
      tokenIssuer: const _StaticDeviceTokenIssuer(
        AuthDeviceAccessToken(
          accessToken: 'unused',
          expiresIn: Duration(minutes: 5),
        ),
      ),
    );
    final emailOtp = EmailOtpPlugin<Object>(
      sendCode: (_) {},
      secret: '0123456789abcdef0123456789abcdef',
    );
    device.configure(AuthServerPluginContext<Object>(store: store));
    emailOtp.configure(AuthServerPluginContext<Object>(store: store));
    store.bindUserDeletionPlanContributors([device, emailOtp]);

    final authorization = AuthDeviceAuthorization(
      id: 'device-1',
      deviceCodeHash: 'device-hash',
      userCodeHash: 'user-hash',
      clientId: 'client-1',
      scopes: const ['openid'],
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      interval: const Duration(seconds: 5),
      userId: user.id,
      status: AuthDeviceAuthorizationStatus.approved,
      approvedAt: now,
    );
    await store.deviceAuthorizations.create(authorization);
    await store.emailOtps.save(
      AuthEmailOtp(
        id: 'otp-1',
        email: user.email!,
        codeHash: digestAuthEmailOtpCode(
          code: '123456',
          secret: 'cloudflare-d1-email-otp-test-key',
        ),
        type: AuthEmailOtpType.signIn,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        maxAttempts: 3,
      ),
    );

    expect(await store.userDeletionCoordinator.deleteUser(user.id), isTrue);
    expect(
      database.select('SELECT * FROM ${schema.table('device_authorizations')}'),
      isEmpty,
    );
    expect(
      database.select('SELECT * FROM ${schema.table('email_otps')}'),
      isEmpty,
    );
  });

  test('D1 deletes core substores after their plugins are removed', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 20, 12);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(
      database,
      schema: schema,
      clock: () => now,
    );
    final user = AuthUser(id: 'removed-plugin-user', email: 'old@example.com');
    await store.users.create(user);
    await store.deviceAuthorizations.create(
      AuthDeviceAuthorization(
        id: 'device-removed',
        deviceCodeHash: 'device-removed-hash',
        userCodeHash: 'user-removed-hash',
        clientId: 'client-1',
        scopes: const ['openid'],
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        interval: const Duration(seconds: 5),
        userId: user.id,
        status: AuthDeviceAuthorizationStatus.approved,
        approvedAt: now,
      ),
    );
    await store.emailOtps.save(
      AuthEmailOtp(
        id: 'otp-removed',
        email: user.email!,
        codeHash: digestAuthEmailOtpCode(
          code: '123456',
          secret: 'cloudflare-d1-email-otp-test-key',
        ),
        type: AuthEmailOtpType.signIn,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        maxAttempts: 3,
      ),
    );
    await store.oauthAuthorizationCodeStore.create(
      OAuthAuthorizationCode(
        authorizationId: 'removed-plugin-authorization',
        codeHash: hashOpaqueToken('removed-plugin-code'),
        clientId: 'removed-plugin-client',
        userId: user.id,
        redirectUri: 'https://removed-plugin.example.test/callback',
        scope: 'profile',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    await store.oauthAccessTokenStore.save(
      OAuthAccessToken(
        authorizationId: 'removed-plugin-token-authorization',
        tokenHash: hashOpaqueToken('removed-plugin-access-token'),
        clientId: 'removed-plugin-client',
        userId: user.id,
        scope: 'profile',
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    store.bindUserDeletionPlanContributors(const []);

    expect(await store.userDeletionCoordinator.deleteUser(user.id), isTrue);

    expect(
      database.select('SELECT * FROM ${schema.table('device_authorizations')}'),
      isEmpty,
    );
    expect(
      database.select('SELECT * FROM ${schema.table('email_otps')}'),
      isEmpty,
    );
    expect(
      database.select(
        'SELECT * FROM ${schema.table('oauth_authorization_codes')}',
      ),
      isEmpty,
    );
    expect(
      database.select('SELECT * FROM ${schema.table('oauth_access_tokens')}'),
      isEmpty,
    );
    await expectLater(
      store.users.create(AuthUser(id: user.id, email: 'new@example.com')),
      throwsStateError,
    );
  });

  test('persists digests rather than raw one-time tokens', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(database, schema: schema);
    const rawToken = 'never-persist-this-value';

    await store.verificationTokens.save(
      AuthVerificationToken(
        identifier: 'digest@example.com',
        token: rawToken,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
    );

    final rows = database.select(
      'SELECT token_hash FROM ${schema.table('verification_tokens')}',
    );
    expect(rows, hasLength(1));
    expect(rows.single['token_hash'], isNot(rawToken));
    expect(rows.single['token_hash'], hashOpaqueToken(rawToken));
  });

  test('returns a distinct result from every atomic JWT rotation', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);

    final versions = await Future.wait([
      for (var i = 0; i < 16; i++)
        Future.sync(() => store.jwtVersions.rotate('rotating-user')),
    ]);

    expect(versions.toSet(), {for (var i = 1; i <= 16; i++) i});
    expect(await store.jwtVersions.current('rotating-user'), 16);
  });

  test(
    'session rotation commits exactly one replacement under contention',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 19, 12);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => now,
      );
      AuthSessionRecord session(String id) => AuthSessionRecord(
        id: id,
        tokenHash: hashOpaqueToken('token-$id'),
        userId: 'rotating-user',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        lastUsedAt: now,
        authenticationMethod: 'credentials',
      );

      final original = session('original');
      await store.sessions.create(original);
      final replacements = [for (var i = 0; i < 16; i++) session('next-$i')];
      final results = await Future.wait([
        for (final replacement in replacements)
          Future.sync(
            () => store.sessions.rotate(
              previousTokenHash: original.tokenHash,
              replacement: replacement,
            ),
          ),
      ]);

      final winner = results.whereType<AuthSessionRecord>().single;
      final stored = await store.sessions.listForUser(original.userId);
      expect(stored, hasLength(2));
      expect(
        stored.singleWhere((value) => value.id == original.id).revokedAt,
        now,
      );
      expect(
        stored.singleWhere((value) => value.id == winner.id).revokedAt,
        isNull,
      );
      for (final losing in replacements.where(
        (value) => value.id != winner.id,
      )) {
        expect(await store.sessions.find(losing.tokenHash), isNull);
      }
    },
  );

  test('leases and completes an approved device authorization once', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 19, 12);
    final store = await CloudflareD1AuthStore.open(database, clock: () => now);
    final authorization = AuthDeviceAuthorization(
      id: 'device-1',
      deviceCodeHash: 'device-hash',
      userCodeHash: 'user-hash',
      clientId: 'client-1',
      scopes: const ['openid'],
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      interval: const Duration(seconds: 5),
    );
    await store.deviceAuthorizations.create(authorization);
    final approvals = await Future.wait([
      for (final userId in ['user-1', 'user-2'])
        Future.sync(
          () => store.deviceAuthorizations.approve(
            authorization.userCodeHash,
            userId,
            now: now,
          ),
        ),
    ]);
    expect(approvals.whereType<AuthDeviceAuthorization>(), hasLength(1));

    final leases = await Future.wait([
      for (var i = 0; i < 8; i++)
        Future.sync(
          () => store.deviceAuthorizations.beginIssuance(
            authorization.deviceCodeHash,
            clientId: authorization.clientId,
            leaseDigest: 'lease-$i',
            leaseExpiresAt: now.add(const Duration(seconds: 30)),
            now: now,
          ),
        ),
    ]);
    final acquired = <int>[
      for (var i = 0; i < leases.length; i++)
        if (leases[i].status ==
            AuthDeviceAuthorizationIssuanceLeaseStatus.acquired)
          i,
    ];
    expect(acquired, hasLength(1));
    expect(
      await store.deviceAuthorizations.completeIssuance(
        authorization.deviceCodeHash,
        clientId: authorization.clientId,
        leaseDigest: 'lease-${acquired.single}',
        now: now,
      ),
      isTrue,
    );
  });

  test('verifies an email OTP once under contention', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 19, 12);
    final store = await CloudflareD1AuthStore.open(database, clock: () => now);
    const code = '123456';
    await store.emailOtps.save(
      AuthEmailOtp(
        id: 'otp-1',
        email: 'otp@example.com',
        codeHash: digestAuthEmailOtpCode(
          code: code,
          secret: 'cloudflare-d1-email-otp-test-key',
        ),
        type: AuthEmailOtpType.signIn,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        maxAttempts: 5,
      ),
    );

    final results = await Future.wait([
      for (var i = 0; i < 8; i++)
        Future.sync(
          () => store.emailOtps.verifyDigest(
            'otp@example.com',
            AuthEmailOtpType.signIn,
            digestAuthEmailOtpCode(
              code: code,
              secret: 'cloudflare-d1-email-otp-test-key',
            ),
            now: now,
          ),
        ),
    ]);
    expect(
      results.where(
        (result) => result.status == AuthEmailOtpVerificationStatus.verified,
      ),
      hasLength(1),
    );
  });
}

AuthAuthenticationMethodService _accountMethodService(
  CloudflareD1AuthStore store,
  Set<String> activeProviderIds,
) => AuthAuthenticationMethodService(
  store: store,
  contributors: [_D1AccountMethodInventory(store.accounts, activeProviderIds)],
)..composeContributors(const []);

OAuthProvider<Map<String, dynamic>> _oauthProvider(String id) =>
    OAuthProvider<Map<String, dynamic>>(
      id: id,
      name: id,
      clientId: 'client',
      clientSecret: 'secret',
      authorizationEndpoint: Uri.https('$id.test', '/authorize'),
      tokenEndpoint: Uri.https('$id.test', '/token'),
      profile: (_) => AuthUser(id: 'unused'),
      redirectUri: 'https://app.test/auth/callback/$id',
    );

final class _D1AccountMethodInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  _D1AccountMethodInventory(this.store, Set<String> activeProviderIds)
    : activeProviderIds = Set.unmodifiable(activeProviderIds);

  final AuthAccountStore store;
  final Set<String> activeProviderIds;

  @override
  String get authenticationMethodNamespace => 'oauth';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.oauthProvider,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async => AuthAuthenticationMethodSnapshot.complete(
    (await store.listForUser(userId)).map(
      (account) => AuthAuthenticationMethod.oauthProvider(
        providerId: account.providerId,
        providerAccountId: account.providerAccountId,
        canAuthenticate: activeProviderIds.contains(account.providerId),
      ),
    ),
  );
}

final class _ExternalMethodInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  final Object _store = Object();

  @override
  String get authenticationMethodNamespace => 'external_passkeys';

  @override
  Object get authenticationMethodStore => _store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.passkey,
  };

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => AuthAuthenticationMethodSnapshot.complete(const []);
}

final class _StaticDeviceTokenIssuer
    implements AuthDeviceAuthorizationTokenIssuer<Object> {
  const _StaticDeviceTokenIssuer(this.token);

  final AuthDeviceAccessToken token;

  @override
  AuthDeviceAccessToken issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<Object> request,
  ) => token;
}

final class _D1DeletionContributor implements AuthUserDeletionPlanContributor {
  _D1DeletionContributor({required this.domain, this.injectFaultOnce = false});

  final CloudflareD1UserDeletionDomain domain;
  final bool injectFaultOnce;
  bool _faultIssued = false;

  @override
  String get userDataNamespace => 'plugin_data';

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) {
    final injectFault = injectFaultOnce && !_faultIssued;
    _faultIssued = _faultIssued || injectFault;
    return CloudflareD1UserDeletionPlan(
      domain: domain,
      userId: user.id,
      namespace: userDataNamespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM plugin_data WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
        if (injectFault)
          CloudflareD1UserDeletionStatement(
            sql:
                'DELETE FROM missing_plugin_data WHERE user_id = ? AND {{guard}}',
            parameters: [user.id],
          ),
      ],
    );
  }
}
