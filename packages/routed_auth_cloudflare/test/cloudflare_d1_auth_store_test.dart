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
      issueToken:
          ({
            required context,
            required user,
            required clientId,
            required scopes,
            required authorizationId,
          }) => const AuthDeviceAccessToken(
            accessToken: 'unused',
            expiresIn: Duration(minutes: 5),
          ),
    );
    final emailOtp = EmailOtpPlugin<Object>(
      sendCode: (_) {},
      rateLimitHashKey: '0123456789abcdef0123456789abcdef',
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
        codeHash: hashAuthEmailOtpCode('123456'),
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
        codeHash: hashAuthEmailOtpCode('123456'),
        type: AuthEmailOtpType.signIn,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        maxAttempts: 3,
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

  test('claims an approved device authorization once', () async {
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

    final claims = await Future.wait([
      for (var i = 0; i < 8; i++)
        Future.sync(
          () => store.deviceAuthorizations.claimApproved(
            authorization.deviceCodeHash,
            clientId: authorization.clientId,
            now: now,
          ),
        ),
    ]);
    expect(claims.whereType<AuthDeviceAuthorization>(), hasLength(1));
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
        codeHash: hashAuthEmailOtpCode(code),
        type: AuthEmailOtpType.signIn,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        maxAttempts: 5,
      ),
    );

    final results = await Future.wait([
      for (var i = 0; i < 8; i++)
        Future.sync(
          () => store.emailOtps.verify(
            'otp@example.com',
            AuthEmailOtpType.signIn,
            code,
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
