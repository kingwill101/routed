import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
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
        if (conformanceCase.optionalCapability ==
            AuthStoreConformanceCapability.accountDeletion) {
          expect(result.isSkipped, isTrue);
          expect(result.skippedReason, contains('accountDeletion'));
        } else {
          expect(result.isSkipped, isFalse, reason: result.skippedReason);
        }
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

  test('fails closed for callback-spanning account deletion', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = await CloudflareD1AuthStore.open(database);

    expect(store, isNot(isA<AuthAccountDeletionStore>()));
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
