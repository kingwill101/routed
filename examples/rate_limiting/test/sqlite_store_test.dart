import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:rate_limiting_example/migrations.dart';
import 'package:rate_limiting_example/sqlite_store.dart';
import 'package:routed_database/routed_database.dart';
import 'package:server_contracts/server_contracts.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String databasePath;
  late OrmDatabase database;
  late DatabaseManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('routed-rate-limit-');
    databasePath = '${directory.path}/rate.sqlite';
    database = await SqliteDatabase.connect(path: databasePath);
    manager = DatabaseManager()..register('default', database);
    await manager.initialize();
    await manager.migrate(appMigrations);
  });

  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });

  test(
    'stores values, atomically increments, and respects expiration',
    () async {
      final store = SqliteRateLimitStore(database);

      expect(await store.add('counter', 1, 0), isTrue);
      expect(await store.add('counter', 2, 0), isFalse);
      expect(await store.increment('counter', 4), 5);
      expect(await store.decrement('counter', 2), 3);
      expect(await store.get('counter'), 3);

      await store.put('temporary', 'value', 1);
      expect(await store.get('temporary'), 'value');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(await store.get('temporary'), isNull);
    },
  );

  test('keeps values after reopening the SQLite file', () async {
    final store = SqliteRateLimitStore(database);
    await store.put('persistent', <String, Object?>{'ok': true}, 0);
    await manager.close();

    final reopened = await SqliteDatabase.connect(path: databasePath);
    addTearDown(reopened.close);
    final persisted = SqliteRateLimitStore(reopened);

    expect(await persisted.get('persistent'), <String, Object?>{'ok': true});
  });

  test('increment preserves an existing expiration window', () async {
    final store = SqliteRateLimitStore(database);
    await store.put('windowed', 1, 60);
    final row =
        (await database
                .table('rate_limit_entries')
                .whereEquals('key', 'windowed')
                .get())
            .single;
    final expiresAt = row['expires_at'];

    expect(await store.increment('windowed'), 2);

    final updated =
        (await database
                .table('rate_limit_entries')
                .whereEquals('key', 'windowed')
                .get())
            .single;
    expect(updated['expires_at'], expiresAt);
  });

  test(
    'provides a database-backed LockProvider for rate-limit state',
    () async {
      final store = SqliteRateLimitStore(database);
      expect(store, isA<LockProvider>());

      final first = await store.lock('rate-limit-lock', 5, 'first-owner');
      final second = await store.lock('rate-limit-lock', 5, 'second-owner');
      expect(await first.acquire(), isTrue);
      expect(await second.acquire(), isFalse);
      expect(await second.getCurrentOwner(), 'first-owner');
      expect(await first.release(), isTrue);
      expect(await second.acquire(), isTrue);
      expect(await second.release(), isTrue);
    },
  );
}
