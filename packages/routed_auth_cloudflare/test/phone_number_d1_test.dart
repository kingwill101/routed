import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 phone authentication', () {
    final suite = AuthPhoneNumberBackendConformanceSuite(() async {
      final database = FakeCloudflareD1Database();
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      store.bindUserDeletionPlanContributors(const []);
      return AuthPhoneNumberBackendConformanceFixture(
        store: store,
        backend: store,
        faults: _D1PhoneFaults(database),
        hardDeleteUser: store.userDeletionCoordinator.deleteUser,
        dispose: database.close,
      );
    });
    for (final testCase in suite.cases) {
      test('conformance: ${testCase.id}', testCase.run);
    }

    test(
      'migration v11 is append-only and dropAll removes phone tables',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        const schema = CloudflareD1AuthSchema(tablePrefix: 'phone_history');

        await schema.migrate(database);

        expect(
          database
              .select(
                'SELECT version FROM ${schema.table('migrations')} '
                'ORDER BY version',
              )
              .map((row) => row['version']),
          orderedEquals(
            List<int>.generate(
              CloudflareD1AuthSchema.currentVersion,
              (index) => index + 1,
            ),
          ),
        );
        expect(
          database.select('SELECT name FROM sqlite_master WHERE name = ?', [
            schema.table('phone_verifications'),
          ]),
          hasLength(1),
        );
        expect(
          database.select('SELECT name FROM sqlite_master WHERE name = ?', [
            schema.table('phone_identities'),
          ]),
          hasLength(1),
        );
        expect(
          database.select('SELECT name FROM sqlite_master WHERE name = ?', [
            schema.table('phone_issue_receipts'),
          ]),
          hasLength(1),
        );

        await schema.dropAll(database);

        expect(
          database.select('SELECT name FROM sqlite_master WHERE name LIKE ?', [
            '${schema.tablePrefix}_%',
          ]),
          isEmpty,
        );
      },
    );

    test('persists only digests and bounded phone metadata', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      const rawId = 'raw-phone-issue-id';
      const rawCode = 'raw-phone-code';
      final codeDigest = hashOpaqueToken(rawCode);
      await store.issuePhoneNumberCode(
        AuthPhoneNumberIssueCodeCommand(
          verification: AuthPhoneNumberVerification(
            id: rawId,
            phoneNumber: '+15555550123',
            codeDigest: codeDigest,
            createdAt: _now,
            expiresAt: _now.add(const Duration(minutes: 5)),
            maxAttempts: 3,
          ),
        ),
      );

      final values = database
          .select('SELECT * FROM ${store.schema.table('phone_verifications')}')
          .single
          .values
          .whereType<String>()
          .join('\n');
      final receiptValues = database
          .select('SELECT * FROM ${store.schema.table('phone_issue_receipts')}')
          .single
          .values
          .whereType<String>()
          .join('\n');
      expect(values, isNot(contains(rawId)));
      expect(values, isNot(contains(rawCode)));
      expect(values, contains(codeDigest));
      expect(receiptValues, isNot(contains(rawId)));
      expect(receiptValues, contains(hashOpaqueToken(rawId)));
    });

    test('challenge and receipt capacities never overflow', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        phoneNumberMaxVerifications: 1,
        clock: () => _now,
      );

      await store.issuePhoneNumberCode(_issue(id: 'first'));
      await store.issuePhoneNumberCode(
        _issue(id: 'second', phoneNumber: '+15555550124'),
      );

      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('phone_verifications')}',
        ),
        hasLength(1),
      );
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('phone_issue_receipts')}',
        ),
        hasLength(2),
      );
    });

    test('hard deletion removes phone identity and challenge state', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      store.bindUserDeletionPlanContributors(const []);
      await store.issuePhoneNumberCode(_issue());
      expect(
        (await store.verifyPhoneNumberCode(
          _verify(candidateId: 'phone-user'),
        )).status,
        AuthPhoneNumberVerifyStatus.verified,
      );

      expect(
        await store.userDeletionCoordinator.deleteUser('phone-user'),
        isTrue,
      );
      expect(await store.findPhoneNumberIdentity('+15555550123'), isNull);
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('phone_verifications')}',
        ),
        isEmpty,
      );
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('phone_issue_receipts')}',
        ),
        isEmpty,
      );
    });

    test(
      'removes phone identity and projection with a durable fallback',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(
          database,
          clock: () => _now,
        );
        final phone = PhoneNumberPlugin<Object>(
          sendCode: (_) {},
          codeHashKey: '0123456789abcdef0123456789abcdef',
        );
        final user = AuthUser(
          id: 'd1-phone-remove-user',
          email: 'd1-phone-remove@example.com',
        );
        await store.credentials.register(
          user,
          AuthPasswordCredential(
            id: 'd1-phone-remove-password',
            userId: user.id,
            identifier: user.email!,
            passwordHash: 'encoded-hash',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: <AuthProvider>[CredentialsProvider()],
            store: store,
            runtimeMode: AuthRuntimeMode.localDevelopment,
            plugins: <AuthServerPlugin<Object>>[phone],
          ),
        );
        await store.issuePhoneNumberCode(_issue());
        final verified = await store.verifyPhoneNumberCode(
          AuthPhoneNumberVerifyCodeCommand(
            phoneNumber: '+15555550123',
            codeDigest: 'phone-digest',
            now: _now,
            candidateUser: user,
          ),
        );
        expect(verified.status, AuthPhoneNumberVerifyStatus.verified);

        await phone.removePhoneNumber(userId: 'd1-phone-remove-user');

        expect(await store.findPhoneNumberIdentity('+15555550123'), isNull);
        final storedUser = await store.users.findById('d1-phone-remove-user');
        expect(storedUser!.attributes, isNot(contains('phoneNumber')));
        expect(storedUser.attributes, isNot(contains('phoneNumberVerified')));
        expect(
          database.select(
            'SELECT * FROM ${store.schema.table('phone_verifications')}',
          ),
          isEmpty,
        );
        expect(
          database.select(
            'SELECT * FROM ${store.schema.table('phone_issue_receipts')}',
          ),
          isEmpty,
        );
      },
    );
  });
}

final class _D1PhoneFaults
    implements AuthPhoneNumberBackendConformanceFaultController {
  _D1PhoneFaults(this.database);

  final FakeCloudflareD1Database database;

  @override
  void failNext(AuthPhoneNumberBackendConformanceFaultPoint point) {
    database.failNextBatchAt = 2;
  }
}

final _now = DateTime.utc(2030);

AuthPhoneNumberIssueCodeCommand _issue({
  String id = 'phone-issue',
  String digest = 'phone-digest',
  String phoneNumber = '+15555550123',
  int maxAttempts = 3,
}) => AuthPhoneNumberIssueCodeCommand(
  verification: AuthPhoneNumberVerification(
    id: id,
    phoneNumber: phoneNumber,
    codeDigest: digest,
    createdAt: _now,
    expiresAt: _now.add(const Duration(minutes: 5)),
    maxAttempts: maxAttempts,
  ),
);

AuthPhoneNumberVerifyCodeCommand _verify({
  String digest = 'phone-digest',
  String? candidateId,
  DateTime? now,
}) => AuthPhoneNumberVerifyCodeCommand(
  phoneNumber: '+15555550123',
  codeDigest: digest,
  now: now ?? _now,
  candidateUser: candidateId == null ? null : AuthUser(id: candidateId),
);
