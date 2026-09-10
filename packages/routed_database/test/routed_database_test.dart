import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_database/routed_database.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('DatabaseManager', () {
    test('registers named connections and resolves the default', () async {
      final defaultDatabase = await SqliteDatabase.connect();
      final reportingDatabase = await SqliteDatabase.connect(name: 'reporting');
      final manager = DatabaseManager()
        ..register('default', defaultDatabase)
        ..register('reporting', reportingDatabase);

      await manager.initialize();

      expect(manager.database(), same(defaultDatabase));
      expect(manager.database(' reporting '), same(reportingDatabase));
      expect(manager.names, containsAll(<String>['default', 'reporting']));

      await manager.close();
      expect(defaultDatabase.isOpen, isFalse);
      expect(reportingDatabase.isOpen, isFalse);
    });

    test('opens a factory once during initialization', () async {
      var opens = 0;
      final manager = DatabaseManager()
        ..registerFactory('default', () async {
          opens += 1;
          return SqliteDatabase.connect();
        });

      await manager.initialize();
      await manager.initialize();

      expect(opens, 1);
      expect(manager.database().isOpen, isTrue);
      await manager.close();
    });

    test('requires a registered default connection', () async {
      final manager = DatabaseManager(defaultConnection: 'missing')
        ..registerFactory('default', SqliteDatabase.connect);

      await expectLater(
        manager.initialize(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('missing'),
          ),
        ),
      );
      await manager.close();
    });

    test('delegates migration entries to the selected connection', () async {
      final database = await SqliteDatabase.connect();
      final manager = DatabaseManager()..register('default', database);
      await manager.initialize();

      final first = await manager.migrate(<MigrationEntry>[
        MigrationEntry.named(
          'm_20260829000100_create_users',
          const _CreateUsersMigration(),
        ),
      ]);
      final second = await manager.migrate(<MigrationEntry>[
        MigrationEntry.named(
          'm_20260829000100_create_users',
          const _CreateUsersMigration(),
        ),
      ]);

      expect(first.actions, hasLength(1));
      expect(second.actions, isEmpty);
      expect(
        (await database.queryRaw(
          'SELECT name FROM sqlite_master',
        )).map((row) => row['name']),
        containsAll(<String>['orm_migrations', 'users']),
      );
      await manager.close();
    });
  });

  test('RoutedDatabaseProvider exposes db from an engine context', () async {
    final database = await SqliteDatabase.connect();
    final manager = DatabaseManager()..register('default', database);
    final engine = Engine(
      providers: <ServiceProvider>[
        ...Engine.defaultProviders,
        RoutedDatabaseProvider(manager: manager),
      ],
    )..get('/db', (ctx) => ctx.string('${identical(ctx.db(), database)}'));
    await engine.initialize();
    final client = TestClient.inMemory(RoutedRequestHandler(engine));

    expect(engine.container.get<DatabaseManager>(), same(manager));
    expect(manager.database(), same(database));
    (await client.get('/db')).assertStatus(200).assertBodyEquals('true');

    await client.close();
    await engine.close();
    expect(database.isOpen, isFalse);
  });

  test('provider can apply migrations during boot when opted in', () async {
    final database = await SqliteDatabase.connect();
    final provider = RoutedDatabaseProvider(
      manager: DatabaseManager()..register('default', database),
      migrations: <MigrationEntry>[
        MigrationEntry.named(
          'm_20260829000200_create_users',
          const _CreateUsersMigration(),
        ),
      ],
      migrateOnBoot: true,
    );
    final engine = await Engine.create(
      providers: <ServiceProvider>[...Engine.defaultProviders, provider],
    );

    expect(provider.lastMigrationReport?.actions, hasLength(1));
    expect(
      (await database.queryRaw(
        'SELECT name FROM sqlite_master',
      )).map((row) => row['name']),
      contains('users'),
    );

    await engine.close();
    expect(database.isOpen, isFalse);
  });

  test('provider boot finishes migrations before the first request', () async {
    var opens = 0;
    final manager = DatabaseManager()
      ..registerFactory('default', () async {
        opens += 1;
        return SqliteDatabase.connect();
      });
    final engine =
        Engine(
          providers: <ServiceProvider>[
            ...Engine.defaultProviders,
            RoutedDatabaseProvider(
              manager: manager,
              migrations: <MigrationEntry>[
                MigrationEntry.named(
                  'm_20260829000300_create_users',
                  const _CreateUsersMigration(),
                ),
              ],
              migrateOnBoot: true,
            ),
          ],
        )..get('/users', (ctx) async {
          final rows = await ctx.db().queryRaw('SELECT email FROM users');
          return ctx.json({'count': rows.length});
        });

    await engine.initialize();
    expect(opens, 1);
    final client = TestClient.inMemory(RoutedRequestHandler(engine));
    final response = await client.get('/users');

    response.assertStatus(200);
    expect(response.json('count'), 0);

    await client.close();
    await engine.close();
  });

  test(
    'provider keeps the database open for request-container cleanup',
    () async {
      final database = await SqliteDatabase.connect();
      final manager = DatabaseManager()..register('default', database);
      final engine = await Engine.create(
        providers: <ServiceProvider>[
          ...Engine.defaultProviders,
          RoutedDatabaseProvider(manager: manager),
        ],
      );

      await engine.cleanupRequestContainer(engine.container.createChild());
      expect(database.isOpen, isTrue);

      await engine.cleanupProviders();
      expect(database.isOpen, isFalse);
    },
  );
}

final class _CreateUsersMigration extends Migration {
  const _CreateUsersMigration();

  @override
  void up(SchemaBuilder schema) {
    schema.create('users', (table) {
      table
        ..increments('id')
        ..string('email');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('users', ifExists: true);
  }
}
