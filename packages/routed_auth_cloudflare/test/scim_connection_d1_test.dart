import 'package:property_testing/property_testing.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 managed SCIM persistence', () {
    final suite = AuthScimConnectionStoreConformanceSuite(() async {
      final database = FakeCloudflareD1Database();
      final store = await CloudflareD1AuthStore.open(database);
      return AuthScimConnectionStoreConformanceFixture(
        store: store.scimConnectionStore,
        dispose: database.close,
      );
    });
    for (final testCase in suite.cases) {
      test('conformance: ${testCase.id}', testCase.run);
    }

    test(
      'persists only the bearer digest and returns the raw secret once',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        const schema = CloudflareD1AuthSchema();
        final store = await CloudflareD1AuthStore.open(
          database,
          schema: schema,
        );
        final plugin = _plugin(store.scimConnectionStore);

        final first = await plugin.create(
          principal: _principal,
          name: 'Directory',
          provisioningDomainId: 'employees',
          scopes: const {AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'create-directory',
        );
        final replay = await plugin.create(
          principal: _principal,
          name: 'Directory',
          provisioningDomainId: 'employees',
          scopes: const {AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'create-directory',
        );

        final rawSecret = first.issuance.secret!;
        expect(replay.issuance.secret, isNull);
        expect(replay.issuance.replayed, isTrue);
        final persisted = [
          ...database.select(
            'SELECT * FROM ${schema.table('scim_connections')}',
          ),
          ...database.select(
            'SELECT * FROM ${schema.table('scim_credentials')}',
          ),
          ...database.select('SELECT * FROM ${schema.table('scim_replays')}'),
        ].expand((row) => row.values).whereType<String>().join('\n');
        expect(persisted, isNot(contains(rawSecret)));
        expect(persisted, isNot(contains('raw-secret-material')));
        expect(persisted, contains(hashOpaqueToken(rawSecret)));
      },
    );

    test(
      'rolls back connection, credential, and replay after a batch fault',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        const schema = CloudflareD1AuthSchema();
        final store = await CloudflareD1AuthStore.open(
          database,
          schema: schema,
        );
        final transaction = _createTransaction();
        var injected = false;
        database.batchFaultInjector = (statementIndex, _) {
          if (!injected && statementIndex == 1) {
            injected = true;
            throw StateError('injected managed SCIM failure');
          }
        };

        await expectLater(
          store.scimConnectionStore.createConnection(transaction),
          throwsA(isA<StateError>()),
        );
        expect(
          database.select('SELECT * FROM ${schema.table('scim_connections')}'),
          isEmpty,
        );
        expect(
          database.select('SELECT * FROM ${schema.table('scim_credentials')}'),
          isEmpty,
        );
        expect(
          database.select('SELECT * FROM ${schema.table('scim_replays')}'),
          isEmpty,
        );

        database.batchFaultInjector = null;
        final retried = await store.scimConnectionStore.createConnection(
          transaction,
        );
        expect(retried.replayed, isFalse);
      },
    );

    test('rotates one credential under contention', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(database);
      final created = await store.scimConnectionStore.createConnection(
        _createTransaction(),
      );
      final replacement = _credential(
        id: 'credential-b',
        digest: 'b' * 64,
        createdAt: _now.add(const Duration(minutes: 1)),
      );
      final transaction = AuthScimRotateCredentialTransaction(
        binding: _binding,
        connectionId: created.connection.id,
        credentialId: created.credential.id,
        replacement: replacement,
        revokedAt: replacement.createdAt,
        idempotency: AuthScimIdempotencyBinding(
          key: 'rotate-credential',
          fingerprint: 'rotate-fingerprint',
        ),
      );

      final results = await Future.wait([
        for (var index = 0; index < 16; index++)
          store.scimConnectionStore.rotateCredential(transaction),
      ]);
      expect(
        results.where((result) => result?.replayed == false),
        hasLength(1),
      );
      expect(
        results.where((result) => result?.replayed == true),
        hasLength(15),
      );
      expect(
        await store.scimConnectionStore.resolveCredentialDigest(
          created.credential.secretDigest,
          now: replacement.createdAt,
        ),
        isNull,
      );
      expect(
        await store.scimConnectionStore.resolveCredentialDigest(
          replacement.secretDigest,
          now: replacement.createdAt,
        ),
        isNotNull,
      );
    });

    test(
      'rolls back a failed credential rotation and permits one retry',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(database);
        final created = await store.scimConnectionStore.createConnection(
          _createTransaction(),
        );
        final replacement = _credential(
          id: 'credential-b',
          digest: 'b' * 64,
          createdAt: _now.add(const Duration(minutes: 1)),
        );
        final transaction = AuthScimRotateCredentialTransaction(
          binding: _binding,
          connectionId: created.connection.id,
          credentialId: created.credential.id,
          replacement: replacement,
          revokedAt: replacement.createdAt,
          idempotency: AuthScimIdempotencyBinding(
            key: 'rotate-rollback',
            fingerprint: 'rotate-rollback-fingerprint',
          ),
        );
        var injected = false;
        database.batchFaultInjector = (statementIndex, _) {
          if (!injected && statementIndex == 1) {
            injected = true;
            throw StateError('injected rotation failure');
          }
        };

        await expectLater(
          store.scimConnectionStore.rotateCredential(transaction),
          throwsA(isA<StateError>()),
        );
        expect(
          await store.scimConnectionStore.resolveCredentialDigest(
            created.credential.secretDigest,
            now: replacement.createdAt,
          ),
          isNotNull,
        );
        expect(
          await store.scimConnectionStore.resolveCredentialDigest(
            replacement.secretDigest,
            now: replacement.createdAt,
          ),
          isNull,
        );

        database.batchFaultInjector = null;
        final retried = await store.scimConnectionStore.rotateCredential(
          transaction,
        );
        expect(retried?.replayed, isFalse);
      },
    );

    test('coordinates SCIM cleanup with durable user deletion', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(database, schema: schema);
      final user = AuthUser(
        id: _principal.subjectId,
        email: 'owner@example.test',
      );
      await store.users.create(user);
      final plugin = _plugin(store.scimConnectionStore)
        ..configure(AuthServerPluginContext<Object>(store: store));
      store.bindUserDeletionPlanContributors([plugin]);
      final created = await plugin.create(
        principal: _principal,
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const {AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'delete-directory',
      );

      expect(await store.userDeletionCoordinator.deleteUser(user.id), isTrue);
      expect(await store.users.findById(user.id), isNull);
      expect(
        await store.scimConnectionStore.findConnection(
          _binding,
          created.connection.id,
        ),
        isNull,
      );
      expect(
        database.select('SELECT * FROM ${schema.table('scim_credentials')}'),
        isEmpty,
      );
      expect(
        database.select('SELECT * FROM ${schema.table('scim_replays')}'),
        isEmpty,
      );
    });

    test(
      'rolls back SCIM cleanup when coordinated deletion fails later',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(database);
        final user = AuthUser(
          id: _principal.subjectId,
          email: 'owner@example.test',
        );
        await store.users.create(user);
        final plugin = _plugin(store.scimConnectionStore)
          ..configure(AuthServerPluginContext<Object>(store: store));
        store.bindUserDeletionPlanContributors([plugin]);
        final created = await plugin.create(
          principal: _principal,
          name: 'Directory',
          provisioningDomainId: 'employees',
          scopes: const {AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'delete-rollback',
        );
        var injected = false;
        database.batchFaultInjector = (statementIndex, _) {
          if (!injected && statementIndex == 1) {
            injected = true;
            throw StateError('injected coordinated deletion failure');
          }
        };

        await expectLater(
          store.userDeletionCoordinator.deleteUser(user.id),
          throwsA(isA<StateError>()),
        );
        expect(await store.users.findById(user.id), isNotNull);
        expect(
          await store.scimConnectionStore.findConnection(
            _binding,
            created.connection.id,
          ),
          isNotNull,
        );

        database.batchFaultInjector = null;
        expect(await store.userDeletionCoordinator.deleteUser(user.id), isTrue);
        expect(await store.users.findById(user.id), isNull);
        expect(
          await store.scimConnectionStore.findConnection(
            _binding,
            created.connection.id,
          ),
          isNull,
        );
      },
    );

    test(
      'property: replay keys cannot be rebound to generated fingerprints',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(database);
        final transaction = _createTransaction();
        await store.scimConnectionStore.createConnection(transaction);
        final runner = PropertyTestRunner<int>(
          Gen.integer(min: 1, max: 1000000),
          (value) async {
            await expectLater(
              store.scimConnectionStore.createConnection(
                AuthScimCreateConnectionTransaction(
                  connection: transaction.connection,
                  credential: transaction.credential,
                  idempotency: AuthScimIdempotencyBinding(
                    key: transaction.idempotency.key,
                    fingerprint: 'different-$value',
                  ),
                ),
              ),
              throwsA(
                isA<AuthScimConnectionStoreException>().having(
                  (error) => error.failure,
                  'failure',
                  AuthScimConnectionStoreFailure.replayMismatch,
                ),
              ),
            );
          },
          PropertyConfig(numTests: 128, seed: 20260828),
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );

    test(
      'property: hostile raw bearer strings never resolve as digests',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(database);
        await store.scimConnectionStore.createConnection(_createTransaction());
        final runner = PropertyTestRunner<int>(
          Gen.integer(min: -1000000, max: 1000000),
          (value) async {
            final candidate = 'raw-$value\r\nauthorization: bearer leaked';
            expect(
              await store.scimConnectionStore.resolveCredentialDigest(
                candidate,
                now: _now,
              ),
              isNull,
            );
          },
          PropertyConfig(numTests: 256, seed: 20260829),
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

final DateTime _now = DateTime.utc(2030, 1, 1, 12);

final AuthScimConnectionBinding _binding = AuthScimConnectionBinding(
  tenantId: 'tenant-a',
  organizationId: 'organization-a',
);

final AuthScimConnectionManagementPrincipal _principal =
    AuthScimConnectionManagementPrincipal(
      tenantId: _binding.tenantId,
      organizationId: _binding.organizationId,
      subjectId: 'user-a',
    );

AuthScimConnectionPlugin<Object> _plugin(AuthScimConnectionStore store) =>
    AuthScimConnectionPlugin<Object>(
      store: store,
      authorize: (_) => _principal,
      connectionIdGenerator: ({int length = 0}) => 'connection-a',
      credentialIdGenerator: ({int length = 0}) => 'credential-a',
      secretGenerator: ({int length = 0}) => 'raw-secret-material',
      clock: () => _now,
    );

AuthScimCreateConnectionTransaction _createTransaction() {
  final connection = AuthScimManagedConnection(
    id: 'connection-a',
    tenantId: _binding.tenantId,
    organizationId: _binding.organizationId,
    provisioningDomainId: 'employees',
    subjectId: _principal.subjectId,
    name: 'Directory',
    scopes: const {AuthScimScope.usersWrite},
    createdAt: _now,
    updatedAt: _now,
  );
  return AuthScimCreateConnectionTransaction(
    connection: connection,
    credential: _credential(
      id: 'credential-a',
      digest: 'a' * 64,
      createdAt: _now,
    ),
    idempotency: AuthScimIdempotencyBinding(
      key: 'create-directory',
      fingerprint: 'create-fingerprint',
    ),
  );
}

AuthScimCredentialRecord _credential({
  required String id,
  required String digest,
  required DateTime createdAt,
}) => AuthScimCredentialRecord(
  id: id,
  connectionId: 'connection-a',
  tenantId: _binding.tenantId,
  organizationId: _binding.organizationId,
  name: 'Primary',
  keyPrefix: 'rscim.cred',
  secretDigest: digest,
  scopes: const {AuthScimScope.usersWrite},
  createdAt: createdAt,
  updatedAt: createdAt,
  expiresAt: createdAt.add(const Duration(days: 30)),
);

String _propertyReport(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';
