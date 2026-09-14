import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:ormed/ormed.dart';
import 'package:server_auth/server_auth.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:test/test.dart';

void main() {
  test('stores digests and consumes a remember token once', () async {
    final database = await SqliteDatabase.connect(path: ':memory:');
    addTearDown(database.close);
    final schema = const OrmAuthSchema(tablePrefix: 'remember_test');
    await schema.migrate(database);
    final store = OrmRememberTokenStore(database, schema: schema);
    final principal = AuthPrincipal(
      id: 'user-1',
      roles: const ['member'],
      attributes: const {'email': 'user@example.com'},
    );

    await store.save(
      'raw-remember-token',
      principal,
      DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

    final read = await store.read('raw-remember-token');
    expect(read?.id, principal.id);
    expect(read?.roles, principal.roles);
    expect(read?.attributes, principal.attributes);
    final consumed = await store.consume('raw-remember-token');
    expect(consumed?.id, principal.id);
    expect(await store.consume('raw-remember-token'), isNull);

    final rows = await database
        .table(
          schema.table('records'),
          columns: const [
            AdHocColumn(name: 'kind', dartType: 'String', isNullable: false),
          ],
        )
        .whereEquals('kind', 'remember')
        .get();
    expect(rows, isEmpty);
    expect(
      rows.any((row) => row.values.contains('raw-remember-token')),
      isFalse,
    );
  });

  test('does not retain an expired token', () async {
    final database = await SqliteDatabase.connect(path: ':memory:');
    addTearDown(database.close);
    final schema = const OrmAuthSchema(tablePrefix: 'remember_expiry_test');
    await schema.migrate(database);
    final store = OrmRememberTokenStore(
      database,
      schema: schema,
      clock: () => DateTime.utc(2026, 1, 1),
    );

    await store.save(
      'expired-token',
      AuthPrincipal(id: 'user-1'),
      DateTime.utc(2025, 12, 31),
    );

    expect(await store.read('expired-token'), isNull);
  });

  test('tombstoning a user removes remember tokens', () async {
    final database = await SqliteDatabase.connect(path: ':memory:');
    addTearDown(database.close);
    final schema = const OrmAuthSchema(tablePrefix: 'remember_tombstone_test');
    await schema.migrate(database);
    final auth = OrmAuthStore(database, schema: schema);
    final store = OrmRememberTokenStore(database, schema: schema);
    final user = AuthUser(id: 'tombstone-user', email: 'tombstone@example.com');
    await auth.users.create(user);
    await store.save(
      'tombstone-token',
      AuthPrincipal(id: user.id),
      DateTime.utc(2030).add(const Duration(minutes: 5)),
    );

    expect(
      await auth.tombstoneUserForAdministration(
        user.id,
        deletedAt: DateTime.utc(2030),
      ),
      isTrue,
    );
    expect(await store.read('tombstone-token'), isNull);
  });
}
