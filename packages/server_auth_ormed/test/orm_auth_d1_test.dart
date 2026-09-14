import 'package:ormed/ormed.dart';
import 'package:ormed_d1/ormed_d1.dart';
import 'package:server_auth/testing.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('supports D1 query operations without a transaction callback', () async {
    final transport = _SqliteD1Transport();
    final database = await D1Database.connect(
      accountId: 'test-account',
      databaseId: 'test-database',
      apiToken: 'test-token',
      transport: transport,
    );
    addTearDown(database.close);

    expect(database.driver.metadata.supportsTransactions, isFalse);
    final auth = await OrmAuthStore.open(
      database,
      schema: const OrmAuthSchema(tablePrefix: 'd1_auth'),
    );
    final organizations = await OrmAuthOrganizationStore.open(
      database,
      schema: const OrmAuthOrganizationSchema(tablePrefix: 'd1_auth'),
    );

    final user = await auth.users.create(
      AuthUser(id: 'd1-user', email: 'd1@example.com'),
    );
    expect((await auth.users.findById(user.id))?.email, user.email);

    final now = DateTime.utc(2030);
    final created = await organizations.createOrganization(
      AuthOrganizationCreateTransaction(
        organization: AuthOrganization(
          id: 'd1-organization',
          name: 'D1 organization',
          slug: 'd1-organization',
          createdAt: now,
          updatedAt: now,
        ),
        creatorMembership: AuthOrganizationMember(
          id: 'd1-membership',
          organizationId: 'd1-organization',
          userId: user.id,
          roles: const ['owner'],
          createdAt: now,
        ),
        organizationLimit: null,
      ),
    );
    expect(created.organization.id, 'd1-organization');
    expect(
      await organizations.findOrganizationBySlug('d1-organization'),
      isNotNull,
    );
  });

  test(
    'executes query-builder operations through an atomic D1 batch',
    () async {
      final transport = _SqliteD1Transport();
      final database = await D1Database.connect(
        accountId: 'test-account',
        databaseId: 'test-database',
        apiToken: 'test-token',
        transport: transport,
      );
      addTearDown(database.close);

      expect(
        database.driver.metadata.supportsCapability(
          DriverCapability.atomicBatches,
        ),
        isTrue,
      );
      await database.executeRaw(
        'CREATE TABLE atomic_probe '
        '(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL)',
      );
      final table = database.table(
        'atomic_probe',
        columns: const [
          AdHocColumn(
            name: 'id',
            dartType: 'int',
            isNullable: false,
            isPrimaryKey: true,
          ),
          AdHocColumn(name: 'value', dartType: 'String', isNullable: false),
        ],
      );

      final results = await database.atomicBatch([
        table.batchInsert([
          <String, Object?>{'value': 'before'},
        ], returning: true),
        table.whereEquals('id', 1).batchUpdate({'value': 'after'}),
        table.whereEquals('id', 1).batchSelect(),
      ]);

      expect(results, hasLength(3));
      expect(results[0].affectedRows, 1);
      expect(results[0].generatedIds, [1]);
      expect(results[1].affectedRows, 1);
      expect(results[2].rows.single['value'], 'after');
      expect(transport.batches, hasLength(1));
      expect(transport.batches.single, hasLength(3));
    },
  );

  test('rolls back all statements when an atomic D1 batch fails', () async {
    final transport = _SqliteD1Transport();
    final database = await D1Database.connect(
      accountId: 'test-account',
      databaseId: 'test-database',
      apiToken: 'test-token',
      transport: transport,
    );
    addTearDown(database.close);

    await database.executeRaw(
      'CREATE TABLE atomic_rollback '
      '(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE)',
    );
    final table = database.table(
      'atomic_rollback',
      columns: const [
        AdHocColumn(
          name: 'id',
          dartType: 'int',
          isNullable: false,
          isPrimaryKey: true,
        ),
        AdHocColumn(name: 'value', dartType: 'String', isNullable: false),
      ],
    );

    await expectLater(
      database.atomicBatch([
        table.batchInsert([
          <String, Object?>{'value': 'kept out'},
        ]),
        table.batchInsert([
          <String, Object?>{'value': 'kept out'},
        ]),
      ]),
      throwsA(isNotNull),
    );
    expect(
      (await database.queryRaw(
        'SELECT COUNT(*) AS count FROM atomic_rollback',
      )).single['count'],
      0,
    );
  });

  test('passes the core auth conformance suite on a D1 transport', () async {
    final suite = AuthStoreConformanceSuite.fromStoreFactory(
      createStore: () async {
        final database = await _openD1Database();
        return OrmAuthStore.open(
          database,
          schema: const OrmAuthSchema(tablePrefix: 'd1_conformance'),
        );
      },
      disposeStore: (store) => (store as OrmAuthStore).database.close(),
    );
    for (final testCase in suite.cases) {
      final result = await testCase.run();
      if (result.isSkipped) continue;
      expect(result.isSkipped, isFalse, reason: '${testCase.id}: $result');
    }
  });

  test('passes organization ownership conformance on a D1 transport', () async {
    final database = await _openD1Database();
    addTearDown(database.close);
    final store = await OrmAuthOrganizationStore.open(
      database,
      schema: const OrmAuthOrganizationSchema(tablePrefix: 'd1_organization'),
    );
    await verifyAuthOrganizationStoreOwnershipConformance(store);
  });

  test(
    'uses one native batch for a successful invitation replacement',
    () async {
      final transport = _SqliteD1Transport();
      final database = await _openD1Database(transport: transport);
      addTearDown(database.close);
      final store = await OrmAuthOrganizationStore.open(
        database,
        schema: const OrmAuthOrganizationSchema(tablePrefix: 'd1_batch'),
      );
      final now = DateTime.utc(2030);
      final organization = AuthOrganization(
        id: 'batch-organization',
        name: 'Batch organization',
        slug: 'batch-organization',
        createdAt: now,
        updatedAt: now,
      );
      final owner = AuthOrganizationMember(
        id: 'batch-owner',
        organizationId: organization.id,
        userId: 'batch-user',
        roles: const ['owner'],
        createdAt: now,
      );
      await store.createOrganization(
        AuthOrganizationCreateTransaction(
          organization: organization,
          creatorMembership: owner,
          organizationLimit: null,
        ),
      );
      final first = AuthOrganizationInvitation(
        id: 'batch-invitation-first',
        organizationId: organization.id,
        email: 'batch@example.com',
        roles: const ['member'],
        inviterId: owner.userId,
        status: AuthOrganizationInvitationStatus.pending,
        expiresAt: now.add(const Duration(days: 1)),
        createdAt: now,
      );
      await store.createInvitation(first);

      final replacement = AuthOrganizationInvitation(
        id: 'batch-invitation-replacement',
        organizationId: first.organizationId,
        email: first.email,
        roles: first.roles,
        inviterId: first.inviterId,
        status: first.status,
        expiresAt: first.expiresAt,
        createdAt: first.createdAt,
        teamId: first.teamId,
        attributes: first.attributes,
      );
      final result = await store.executeOrganizationMutation(
        AuthOrganizationCreateInvitationCommand(
          actorMembership: owner,
          invitation: replacement,
          invitationLimit: null,
          replacePending: true,
          idempotency: AuthOrganizationIdempotency(
            key: 'batch-replace-key',
            organizationId: organization.id,
            actorId: owner.userId,
            operationId: 'organization.inviteMember',
            fingerprint: 'batch-replace-fingerprint',
          ),
        ),
      );

      expect(result.value.id, replacement.id);
      expect(transport.batches, hasLength(1));
      expect(transport.batches.single, hasLength(3));
      expect(
        (await store.findInvitation(first.id))?.status,
        AuthOrganizationInvitationStatus.canceled,
      );
      expect(
        (await store.findInvitation(replacement.id))?.status,
        AuthOrganizationInvitationStatus.pending,
      );
    },
  );
}

Future<OrmDatabase> _openD1Database({_SqliteD1Transport? transport}) =>
    D1Database.connect(
      accountId: 'test-account',
      databaseId: 'test-database',
      apiToken: 'test-token',
      transport: transport ?? _SqliteD1Transport(),
    );

final class _SqliteD1Transport implements D1Transport, D1BatchTransport {
  _SqliteD1Transport() : _database = sqlite3.openInMemory();

  final Database _database;
  final List<List<D1Statement>> batches = [];

  @override
  Future<D1StatementResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final rows = _database.select(sql, parameters);
    return D1StatementResult(
      rows: [
        for (final row in rows)
          <String, Object?>{for (final key in row.keys) key: row[key]},
      ],
      meta: {'rows_read': rows.length},
    );
  }

  @override
  Future<D1StatementResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _database.execute(sql, parameters);
    return D1StatementResult(
      meta: {
        'changes': _database.updatedRows,
        'last_row_id': _database.lastInsertRowId,
      },
    );
  }

  @override
  Future<List<D1StatementResult>> batch(
    Iterable<D1Statement> statements,
  ) async {
    final batch = List<D1Statement>.from(statements);
    batches.add(batch);
    _database.execute('BEGIN');
    try {
      final results = <D1StatementResult>[];
      for (final statement in batch) {
        final sql = statement.sql.trimLeft();
        final upperSql = sql.toUpperCase();
        if (upperSql.startsWith('SELECT') ||
            upperSql.startsWith('PRAGMA') ||
            upperSql.contains(' RETURNING ')) {
          final rows = _database.select(statement.sql, statement.parameters);
          results.add(
            D1StatementResult(
              rows: [
                for (final row in rows)
                  <String, Object?>{for (final key in row.keys) key: row[key]},
              ],
              meta: {
                'rows_read': rows.length,
                if (upperSql.contains(' RETURNING ')) 'changes': rows.length,
              },
            ),
          );
        } else {
          _database.execute(statement.sql, statement.parameters);
          results.add(
            D1StatementResult(
              meta: {
                'changes': _database.updatedRows,
                'last_row_id': _database.lastInsertRowId,
              },
            ),
          );
        }
      }
      _database.execute('COMMIT');
      return results;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> close() async => _database.close();
}
