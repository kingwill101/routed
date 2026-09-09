import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:server_cache/server_cache.dart';
import 'package:test/test.dart';

void main() {
  late OrmDatabase database;
  late OrmCacheStore store;

  setUp(() async {
    database = await SqliteDatabase.connect();
    store = OrmCacheStore(database);
    await database.migrate([store.migration]);
  });

  tearDown(() => database.close());

  test('persists JSON values and enumerates keys', () async {
    expect(await store.put('user', {'id': 42, 'active': true}, 60), isTrue);
    expect(await store.put('nullable', null, 60), isTrue);

    expect(await store.get('user'), {'id': 42, 'active': true});
    expect(await store.many(['user', 'missing']), {
      'user': {'id': 42, 'active': true},
      'missing': null,
    });
    expect(await store.getAllKeys(), containsAll(<String>['user', 'nullable']));
  });

  test(
    'add is store-only-if-absent and expired entries can be replaced',
    () async {
      expect(await store.add('once', 'first', 60), isTrue);
      expect(await store.add('once', 'second', 60), isFalse);
      expect(await store.get('once'), 'first');

      expect(await store.put('short', 'old', 1), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(await store.add('short', 'new', 60), isTrue);
      expect(await store.get('short'), 'new');
    },
  );

  test('increments and decrements retain the existing expiration', () async {
    await store.put('counter', 1, 60);
    expect(await store.increment('counter', 4), 5);
    expect(await store.decrement('counter', 2), 3);
    expect(await store.get('counter'), 3);

    expect(await store.increment('new-counter'), 1);
    expect(await store.get('new-counter'), 1);
  });

  test('supports bulk writes, forever, forget, and flush', () async {
    expect(await store.putMany({'one': 1, 'two': 2}, 60), isTrue);
    expect(await store.forever('forever', 'value'), isTrue);
    expect(await store.forget('one'), isTrue);
    expect(await store.forget('one'), isFalse);
    expect(await store.get('one'), isNull);

    expect(await store.flush(), isTrue);
    expect(await store.getAllKeys(), isEmpty);
  });

  test('creates a separate table for a custom identifier', () async {
    final custom = OrmCacheStore(database, tableName: 'test_cache_entries');
    await database.migrate([custom.migration]);

    await custom.put('key', 'value', 60);
    expect(await custom.get('key'), 'value');
    expect(await store.get('key'), isNull);
  });

  test('rejects unsafe table identifiers', () {
    expect(
      () => OrmCacheStore(database, tableName: 'cache entries'),
      throwsArgumentError,
    );
  });
}
