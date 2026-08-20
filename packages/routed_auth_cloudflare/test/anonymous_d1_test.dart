import 'dart:async';

import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 anonymous mutation conformance', () {
    final suite = AuthAnonymousStoreConformanceSuite(() async {
      final database = FakeCloudflareD1Database();
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => DateTime.utc(2030),
      );
      final faults = _D1AnonymousFaultController(database);
      _bindAnonymousPlugin(store);
      return AuthAnonymousStoreConformanceFixture(
        store: store,
        mutations: store,
        faults: faults,
        dispose: database.close,
      );
    });

    for (final conformanceCase in suite.cases) {
      test(conformanceCase.description, conformanceCase.run);
    }
  });

  test('migration 7 appends anonymous tables after versions 1 through 6', () {
    const schema = CloudflareD1AuthSchema();
    final anonymousMigration = schema.migrations.singleWhere(
      (migration) => migration.version == 7,
    );

    expect(CloudflareD1AuthSchema.currentVersion, greaterThanOrEqualTo(7));
    expect(
      schema.migrations.map((migration) => migration.version),
      orderedEquals(
        List<int>.generate(
          CloudflareD1AuthSchema.currentVersion,
          (index) => index + 1,
        ),
      ),
    );
    expect(
      anonymousMigration.statements.join('\n'),
      allOf(
        contains('routed_auth_anonymous_mutation_guards'),
        contains('routed_auth_anonymous_mutation_receipts'),
      ),
    );
  });

  test(
    'receipts are digest-only and bounded by the typed store limit',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      var now = DateTime.utc(2030);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(
        database,
        schema: schema,
        anonymousMaxReceipts: 2,
        clock: () => now,
      );
      _bindAnonymousPlugin(store);

      for (var index = 0; index < 3; index++) {
        await store.createAnonymousAccount(
          AuthAnonymousCreateAccountCommand(
            operationId: 'raw-operation-$index',
            user: AuthUser(
              id: 'raw-anonymous-user-$index',
              name: 'Guest $index',
              isAnonymous: true,
            ),
          ),
        );
        now = now.add(const Duration(seconds: 1));
      }

      final table = schema.table('anonymous_mutation_receipts');
      final rows = database.select('SELECT * FROM $table ORDER BY created_at');
      expect(rows, hasLength(2));
      final persistedValues = rows
          .expand((row) => row.values)
          .whereType<String>()
          .join('\n');
      expect(persistedValues, isNot(contains('raw-operation-')));
      expect(persistedValues, isNot(contains('raw-anonymous-user-')));
      expect(persistedValues, isNot(contains('Guest')));
      expect(
        database.select('PRAGMA table_info($table)').map((row) => row['name']),
        orderedEquals([
          'operation_id_hash',
          'operation_type',
          'fingerprint_hash',
          'subject_user_id_hash',
          'target_user_id_hash',
          'created_at',
          'expires_at',
        ]),
      );
    },
  );

  test('generic hard deletion scrubs subject receipts in its batch', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(database, schema: schema);
    _bindAnonymousPlugin(store);
    const userId = 'generic-hard-delete-anonymous';
    await store.createAnonymousAccount(
      AuthAnonymousCreateAccountCommand(
        operationId: 'generic-hard-delete-operation',
        user: AuthUser(id: userId, isAnonymous: true),
      ),
    );
    final table = schema.table('anonymous_mutation_receipts');
    expect(database.select('SELECT * FROM $table'), hasLength(1));

    expect(await store.userDeletionCoordinator.deleteUser(userId), isTrue);

    expect(database.select('SELECT * FROM $table'), isEmpty);
    expect(await store.users.findById(userId), isNull);
  });

  test('rejected creation does not evict retained receipts', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(
      database,
      schema: schema,
      anonymousMaxReceipts: 2,
    );
    _bindAnonymousPlugin(store);
    for (final userId in ['retained-a', 'retained-b']) {
      await store.createAnonymousAccount(
        AuthAnonymousCreateAccountCommand(
          operationId: 'create-$userId',
          user: AuthUser(id: userId, isAnonymous: true),
        ),
      );
    }
    final table = schema.table('anonymous_mutation_receipts');
    final before = database
        .select('SELECT operation_id_hash FROM $table')
        .map((row) => row['operation_id_hash'])
        .toSet();

    await expectLater(
      store.createAnonymousAccount(
        AuthAnonymousCreateAccountCommand(
          operationId: 'rejected-conflict',
          user: AuthUser(id: 'retained-a', isAnonymous: true),
        ),
      ),
      throwsStateError,
    );

    expect(
      database
          .select('SELECT operation_id_hash FROM $table')
          .map((row) => row['operation_id_hash'])
          .toSet(),
      before,
    );
  });

  test(
    'concurrent hard deletion cannot leave a late creation receipt',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(database, schema: schema);
      _bindAnonymousPlugin(store);
      final createCommitted = Completer<void>();
      final returnCreate = Completer<void>();
      database.afterBatchCommit = () async {
        createCommitted.complete();
        await returnCreate.future;
      };
      final command = AuthAnonymousCreateAccountCommand(
        operationId: 'concurrent-hard-delete-create',
        user: AuthUser(id: 'concurrent-hard-delete-user', isAnonymous: true),
      );

      final creation = store.createAnonymousAccount(command);
      await createCommitted.future;
      database.afterBatchCommit = null;
      expect(
        await store.userDeletionCoordinator.deleteUser(command.user.id),
        isTrue,
      );
      returnCreate.complete();

      expect(
        (await creation).status,
        AuthAnonymousMutationStatus.applied,
        reason: 'the D1 create batch linearized before hard deletion',
      );
      expect(await store.users.findById(command.user.id), isNull);
      expect(
        database.select(
          'SELECT * FROM ${schema.table('anonymous_mutation_receipts')}',
        ),
        isEmpty,
      );
      await expectLater(
        store.createAnonymousAccount(command),
        throwsStateError,
      );
    },
  );

  test(
    'contended operation-ID mismatch rolls back the losing subject',
    () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(database);
      _bindAnonymousPlugin(store);
      for (final userId in ['source-a', 'source-b']) {
        await store.createAnonymousAccount(
          AuthAnonymousCreateAccountCommand(
            operationId: 'create-$userId',
            user: AuthUser(id: userId, isAnonymous: true),
          ),
        );
      }

      final results = await Future.wait([
        store.deleteAnonymousAccount(
          AuthAnonymousDeleteAccountCommand(
            operationId: 'shared-delete-operation',
            userId: 'source-a',
          ),
        ),
        store.deleteAnonymousAccount(
          AuthAnonymousDeleteAccountCommand(
            operationId: 'shared-delete-operation',
            userId: 'source-b',
          ),
        ),
      ]);

      expect(
        results.map((result) => result.status),
        containsAll([
          AuthAnonymousMutationStatus.applied,
          AuthAnonymousMutationStatus.replayMismatch,
        ]),
      );
      final survivors = [
        for (final userId in ['source-a', 'source-b'])
          if (await store.users.findById(userId) != null) userId,
      ];
      expect(survivors, hasLength(1));
    },
  );

  test('missing migration fails closed without process-local state', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final store = CloudflareD1AuthStore(database);
    final plugin = AnonymousPlugin<Object>();
    plugin.configure(AuthServerPluginContext<Object>(store: store));
    store.bindUserDeletionPlanContributors([plugin]);

    await expectLater(
      plugin.signInAnonymous(context: Object()),
      throwsA(anything),
    );
    expect(
      database.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
      isEmpty,
    );
  });
}

void _bindAnonymousPlugin(CloudflareD1AuthStore store) {
  final plugin = AnonymousPlugin<Object>();
  plugin.configure(AuthServerPluginContext<Object>(store: store));
  store.bindUserDeletionPlanContributors([plugin]);
}

final class _D1AnonymousFaultController
    implements AuthAnonymousStoreConformanceFaultController {
  _D1AnonymousFaultController(this.database);

  final FakeCloudflareD1Database database;

  @override
  void failNext(AuthAnonymousStoreConformanceFaultPoint point) {
    database.failNextBatchAfterStatements(switch (point) {
      AuthAnonymousStoreConformanceFaultPoint.afterCreateWrite => 4,
      AuthAnonymousStoreConformanceFaultPoint.duringDelete => 15,
      AuthAnonymousStoreConformanceFaultPoint.duringUpgrade => 15,
    });
  }
}
