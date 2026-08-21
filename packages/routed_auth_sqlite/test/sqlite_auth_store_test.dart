import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteAuthStore conformance', () {
    final suite = AuthStoreConformanceSuite.fromStoreFactory(
      createStore: SqliteAuthStore.openInMemory,
      disposeStore: (store) => (store as SqliteAuthStore).close(),
    );

    for (final conformanceCase in suite.cases) {
      test(conformanceCase.description, () async {
        final result = await conformanceCase.run();
        if (result.isSkipped) {
          markTestSkipped(result.skippedReason!);
        }
      });
    }
  });

  test('persists typed auth state across file-backed reopen', () async {
    final directory = await Directory.systemTemp.createTemp('routed-auth-');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'auth.sqlite');

    final first = await SqliteAuthStore.openPath(path);
    await first.users.create(
      AuthUser(id: 'user-1', email: 'person@example.com'),
    );
    await first.sessions.create(
      AuthSessionRecord(
        id: 'session-1',
        userId: 'user-1',
        tokenHash: 'token-hash',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        lastUsedAt: DateTime.utc(2026, 1, 1),
        authenticationMethod: 'password',
      ),
    );
    first.close();

    final second = await SqliteAuthStore.openPath(path);
    addTearDown(second.close);
    expect(
      (await second.users.findByEmail('person@example.com'))?.id,
      equals('user-1'),
    );
    expect((await second.sessions.find('token-hash'))?.id, equals('session-1'));
  });

  test('rolls back a failed multi-statement batch', () async {
    final store = await SqliteAuthStore.openInMemory();
    addTearDown(store.close);

    store.database.execute('BEGIN IMMEDIATE');
    try {
      store.database.execute(
        'INSERT INTO routed_auth_users (id, email, payload) '
        "VALUES ('rollback-user', 'rollback@example.com', '{}')",
      );
      store.database.execute(
        'INSERT INTO routed_auth_users (id, email, payload) '
        "VALUES ('rollback-user', 'other@example.com', '{}')",
      );
    } catch (_) {
      store.database.execute('ROLLBACK');
    }

    expect(await store.users.findById('rollback-user'), isNull);
  });
}
