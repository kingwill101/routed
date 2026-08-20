import 'package:property_testing/property_testing.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 API-key persistence', () {
    final suite = AuthApiKeyStoreConformanceSuite(({
      int maxRecords = 10000,
    }) async {
      final database = FakeCloudflareD1Database();
      final store = await CloudflareD1AuthStore.open(
        database,
        apiKeyMaxRecords: maxRecords,
        clock: () => _now,
      );
      return AuthApiKeyStoreConformanceFixture(
        store: store.apiKeys,
        faults: _D1ApiKeyFaults(database),
        dispose: database.close,
      );
    });
    for (final testCase in suite.cases) {
      test('conformance: ${testCase.id}', testCase.run);
    }

    test('persists the digest but never the one-time raw key', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(
        database,
        schema: schema,
        clock: () => _now,
      );
      final plugin = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        keyIdGenerator: ({int length = 32}) => 'service-key-id',
        secretGenerator: ({int length = 32}) => 'raw-service-secret',
        clock: () => _now,
      );

      final issued = await plugin.issue(
        userId: 'user-1',
        name: 'Worker',
        scopes: const ['jobs:read', 'jobs:write'],
      );
      final values = database
          .select('SELECT * FROM ${schema.table('api_keys')}')
          .single
          .values
          .whereType<String>()
          .join('\n');

      expect(values, isNot(contains(issued.key)));
      expect(values, isNot(contains('raw-service-secret')));
      expect(values, contains(hashOpaqueToken(issued.key)));
      expect((await plugin.authenticate(issued.key))?.record.userId, 'user-1');
    });

    test('migration v9 is append-only and dropAll removes API keys', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema(tablePrefix: 'api_key_history');
      await schema.migrate(database);
      final store = CloudflareD1AuthStore(database, schema: schema);
      await store.apiKeys.create(_record('drop-all'));

      expect(
        database
            .select(
              'SELECT version FROM ${schema.table('migrations')} '
              'ORDER BY version',
            )
            .map((row) => row['version']),
        orderedEquals([1, 2, 3, 4, 5, 6, 7, 8, 9]),
      );
      expect(
        database.select('SELECT * FROM ${schema.table('api_keys')}'),
        hasLength(1),
      );
      expect(
        database.select("SELECT name FROM sqlite_master WHERE name = ?", [
          schema.table('magic_links'),
        ]),
        hasLength(1),
      );
      expect(
        database
            .select('PRAGMA table_info(${schema.table('email_otps')})')
            .map((row) => row['name']),
        contains('verification_marker'),
      );

      await schema.dropAll(database);

      expect(
        database.select("SELECT name FROM sqlite_master WHERE name = ?", [
          schema.table('api_keys'),
        ]),
        isEmpty,
      );
    });

    test('hard deletion removes keys in the coordinator batch', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final plugin = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        clock: () => _now,
      );
      final methods = AuthAuthenticationMethodService(store: store);
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      store.bindUserDeletionPlanContributors([plugin]);
      await store.users.create(AuthUser(id: 'user-1'));
      final issued = await plugin.issue(userId: 'user-1', name: 'Worker');

      expect(await store.userDeletionCoordinator.deleteUser('user-1'), isTrue);

      expect(await store.apiKeys.findById(issued.apiKey.id), isNull);
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('api_keys')} WHERE user_id = ?',
          ['user-1'],
        ),
        isEmpty,
      );
      await expectLater(
        store.apiKeys.create(_record('after-delete')),
        throwsStateError,
      );
    });

    test('hard-deletion plan rolls back with root deletion', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final plugin = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        clock: () => _now,
      );
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: AuthAuthenticationMethodService(store: store),
        ),
      );
      store.bindUserDeletionPlanContributors([plugin]);
      await store.users.create(AuthUser(id: 'user-1'));
      final issued = await plugin.issue(userId: 'user-1', name: 'Worker');
      database.failNextBatchAfterStatements(1);

      await expectLater(
        store.userDeletionCoordinator.deleteUser('user-1'),
        throwsStateError,
      );

      expect(await store.users.findById('user-1'), isNotNull);
      expect(await store.apiKeys.findById(issued.apiKey.id), isNotNull);
      expect(await store.userDeletionCoordinator.deleteUser('user-1'), isTrue);
      expect(await store.users.findById('user-1'), isNull);
      expect(await store.apiKeys.findById(issued.apiKey.id), isNull);
    });

    test('backend-owned hard deletion survives plugin removal', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      store.bindUserDeletionPlanContributors(const []);
      await store.users.create(AuthUser(id: 'user-1'));
      await store.apiKeys.create(_record('removed-plugin'));

      expect(await store.userDeletionCoordinator.deleteUser('user-1'), isTrue);

      expect(await store.apiKeys.findById('key-removed-plugin'), isNull);
    });

    test('primary revocation uses exact authoritative D1 topology', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final plugin = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        countsAsPrimaryAuthenticationMethod: true,
        clock: () => _now,
      );
      final methods = AuthAuthenticationMethodService(store: store);
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([
        plugin,
        _EmailMethodContributor(store.users),
      ]);
      final issued = await plugin.issue(userId: 'user-1', name: 'Primary');

      final revoked = await plugin.revoke(
        'user-1',
        issued.apiKey.id,
        now: _now,
      );

      expect(revoked?.revokedAt, _now);
      expect(await plugin.authenticate(issued.key, now: _now), isNull);
    });

    test(
      'primary API keys preserve the last method and allow a key fallback',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(
          database,
          clock: () => _now,
        );
        await store.users.create(AuthUser(id: 'user-1'));
        var keyIndex = 0;
        final plugin = AuthApiKeyPlugin<Object>(
          store: store.apiKeys,
          countsAsPrimaryAuthenticationMethod: true,
          keyIdGenerator: ({int length = 32}) => 'key-${keyIndex++}',
          secretGenerator: ({int length = 32}) => 'secret-${keyIndex++}',
          clock: () => _now,
        );
        final methods = AuthAuthenticationMethodService(store: store);
        plugin.configure(
          AuthServerPluginContext<Object>(
            store: store,
            authenticationMethods: methods,
          ),
        );
        methods.composeContributors([plugin]);
        final first = await plugin.issue(userId: 'user-1', name: 'First');

        await expectLater(
          plugin.revoke('user-1', first.apiKey.id, now: _now),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'last_authentication_method',
            ),
          ),
        );
        final second = await plugin.issue(userId: 'user-1', name: 'Second');
        expect(
          await plugin.revoke('user-1', first.apiKey.id, now: _now),
          isNotNull,
        );
        expect(await plugin.authenticate(first.key, now: _now), isNull);
        expect(await plugin.authenticate(second.key, now: _now), isNotNull);
      },
    );

    test('mixed authentication stores fail closed without mutation', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      await store.users.create(AuthUser(id: 'user-1'));
      final plugin = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        countsAsPrimaryAuthenticationMethod: true,
        clock: () => _now,
      );
      final methods = AuthAuthenticationMethodService(store: store);
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([
        plugin,
        _ForeignMethodContributor(InMemoryAuthApiKeyStore()),
      ]);
      final issued = await plugin.issue(userId: 'user-1', name: 'Primary');

      await expectLater(
        plugin.revoke('user-1', issued.apiKey.id, now: _now),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'authentication_method_mutation_unavailable',
          ),
        ),
      );
      expect(await plugin.authenticate(issued.key, now: _now), isNotNull);
    });

    test('hostile identifiers remain bound values or are rejected', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        apiKeyMaxRecords: 2000,
        clock: () => _now,
      );
      final generator = Gen.frequency<String>([
        (8, Chaos.string(minLength: 0, maxLength: 600)),
        (
          2,
          Gen.oneOf([
            '',
            ' ',
            'user\u0000admin',
            'user\nadmin',
            "' OR 1=1 --",
            '../../keys',
            '<script>alert(1)</script>',
            '正常な利用者',
            'x' * 513,
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (candidate) async {
        try {
          await store.apiKeys.create(_record('property', userId: candidate));
          expect(candidate, isNotEmpty);
          expect(candidate, candidate.trim());
          expect(candidate.length, lessThanOrEqualTo(512));
          expect(
            candidate.runes.any((rune) => rune < 0x20 || rune == 0x7f),
            isFalse,
          );
          await store.apiKeys.deleteForUser(candidate);
        } on ArgumentError {
          expect(
            candidate.isEmpty ||
                candidate != candidate.trim() ||
                candidate.length > 512 ||
                candidate.runes.any((rune) => rune < 0x20 || rune == 0x7f),
            isTrue,
          );
        }
      }, PropertyConfig(numTests: 400, seed: 20260830));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
      expect(
        database.select('SELECT * FROM ${store.schema.table('api_keys')}'),
        isEmpty,
      );
    });

    test(
      'stateful operations preserve capacity and rotation invariants',
      () async {
        final generator = Gen.integer(
          min: -100000,
          max: 100000,
        ).list(minLength: 1, maxLength: 50);
        final runner = PropertyTestRunner<List<int>>(generator, (
          operations,
        ) async {
          final database = FakeCloudflareD1Database();
          try {
            final maxRecords = 1 + (operations.first.abs() % 8);
            final store = await CloudflareD1AuthStore.open(
              database,
              apiKeyMaxRecords: maxRecords,
              clock: () => _now,
            );
            var serial = 0;
            await store.apiKeys.create(_record('state-${serial++}'));

            for (final operation in operations) {
              final records = await store.apiKeys.listForUser('user-1');
              final active = records
                  .where((record) => record.isActive(now: _now))
                  .toList(growable: false);
              switch (operation.abs() % 5) {
                case 0:
                  try {
                    await store.apiKeys.create(_record('state-${serial++}'));
                  } on StateError {
                    // A full store rejects creation without exceeding its bound.
                  }
                case 1:
                  if (active.isNotEmpty) {
                    final old = active[operation.abs() % active.length];
                    final replacement = _record('state-${serial++}');
                    expect(
                      await store.apiKeys.rotateForUser(
                        userId: old.userId,
                        id: old.id,
                        replacement: replacement,
                        revokedAt: _now,
                      ),
                      isNotNull,
                    );
                    expect(
                      await store.apiKeys.touchIfActive(old.id, _now),
                      isNull,
                    );
                  }
                case 2:
                  if (active.isNotEmpty) {
                    final selected = active[operation.abs() % active.length];
                    expect(
                      await store.apiKeys.revokeForUser(
                        selected.userId,
                        selected.id,
                        revokedAt: _now,
                      ),
                      isNotNull,
                    );
                  }
                case 3:
                  if (active.isNotEmpty) {
                    final selected = active[operation.abs() % active.length];
                    expect(
                      await store.apiKeys.touchIfActive(selected.id, _now),
                      isNotNull,
                    );
                  }
                case 4:
                  try {
                    await store.apiKeys.create(
                      _record(
                        'state-${serial++}',
                        expiresAt: _now.subtract(const Duration(seconds: 1)),
                      ),
                    );
                  } on StateError {
                    // Capacity rejection is valid and must leave the bound intact.
                  }
              }

              final rows = database.select(
                'SELECT * FROM ${store.schema.table('api_keys')}',
              );
              expect(rows.length, lessThanOrEqualTo(maxRecords));
              expect(
                rows.map((row) => row['id']).toSet(),
                hasLength(rows.length),
              );
              expect(
                rows.map((row) => row['secret_hash']).whereType<String>(),
                everyElement(allOf(hasLength(43), isNot(contains('raw-')))),
              );
              expect(
                rows.map((row) => row['rotation_marker']),
                everyElement(isNull),
              );
            }
          } finally {
            database.close();
          }
        }, PropertyConfig(numTests: 200, seed: 20260831));

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

final DateTime _now = DateTime.utc(2030, 1, 1);

AuthApiKeyRecord _record(
  String suffix, {
  String userId = 'user-1',
  DateTime? expiresAt,
}) => AuthApiKeyRecord(
  id: 'key-$suffix',
  userId: userId,
  name: 'Key $suffix',
  keyPrefix: 'rka.key-$suffix',
  secretHash: hashOpaqueToken('raw-$suffix-secret'),
  scopes: const ['jobs:read'],
  createdAt: _now,
  updatedAt: _now,
  expiresAt: expiresAt ?? _now.add(const Duration(days: 1)),
);

final class _D1ApiKeyFaults
    implements AuthApiKeyStoreConformanceFaultController {
  const _D1ApiKeyFaults(this.database);

  final FakeCloudflareD1Database database;

  @override
  void failNext(AuthApiKeyStoreConformanceFaultPoint point) {
    switch (point) {
      case AuthApiKeyStoreConformanceFaultPoint.afterRotationInsert:
        database.failNextBatchAfterStatements(2);
    }
  }
}

final class _EmailMethodContributor
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _EmailMethodContributor(this.store);

  final AuthUserStore store;

  @override
  String get authenticationMethodNamespace => 'email:test';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.emailLink,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    final user = await store.findById(userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (user?.email != null)
        AuthAuthenticationMethod.emailLink(providerId: 'test', userId: userId),
    ]);
  }
}

final class _ForeignMethodContributor
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _ForeignMethodContributor(this.store);

  final Object store;

  @override
  String get authenticationMethodNamespace => 'foreign';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.plugin,
  };

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => AuthAuthenticationMethodSnapshot.complete([
    AuthAuthenticationMethod.plugin(namespace: 'foreign', id: userId),
  ]);
}

String _propertyReport(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';
