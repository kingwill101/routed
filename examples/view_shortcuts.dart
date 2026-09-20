import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';

const _userColumns = <AdHocColumn>[
  AdHocColumn(
    name: 'id',
    dartType: 'int',
    columnType: 'INTEGER',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'name', dartType: 'String', isNullable: false),
];

final class CreateViewUsersTable extends Migration {
  const CreateViewUsersTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('view_users', (table) {
      table
        ..increments('id')
        ..string('name');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('view_users', ifExists: true);
  }
}

/// Demonstrates the `requireFound` and `fetchOr404` helpers for view logic.
Future<void> main() async {
  final databasePath =
      Platform.environment['DATABASE_PATH'] ?? 'storage/view_shortcuts.sqlite';
  File(databasePath).absolute.parent.createSync(recursive: true);
  final database = await SqliteDatabase.connect(path: databasePath);
  final databases = DatabaseManager()..register('default', database);
  final engine = Engine(
    providers: [
      RoutedDatabaseProvider(
        manager: databases,
        migrations: [
          MigrationEntry.named(
            'm_20260908000400_create_view_users',
            const CreateViewUsersTable(),
          ),
        ],
        migrateOnBoot: true,
      ),
      ...Engine.defaultProviders,
    ],
  );

  engine.get('/users/{id}', (ctx) async {
    final id = ctx.mustGetParam<String>('id');

    final user = await ctx.fetchOr404(() async {
      final userId = int.tryParse(id);
      if (userId == null) return null;
      final rows = await ctx
          .db()
          .table('view_users', columns: _userColumns)
          .whereEquals('id', userId)
          .limit(1)
          .get();
      if (rows.isEmpty) return null;
      return {'id': rows.first['id'].toString(), 'name': rows.first['name']};
    }, message: 'User not found');
    return ctx.json(user);
  });

  engine.get('/sessions/current', (ctx) async {
    final session = ctx.requireFound(
      ctx.headers.value('x-session-id'),
      message: 'Session missing',
    );
    return ctx.json({'sessionId': session});
  });

  await engine.initialize();
  final users = await database.table('view_users', columns: _userColumns).get();
  if (users.isEmpty) {
    await database.table('view_users', columns: _userColumns).insertManyInputs([
      {'id': 1, 'name': 'Ada Lovelace'},
      {'id': 2, 'name': 'Alan Turing'},
    ], returning: false);
  }
  await engine.serve(host: '127.0.0.1', port: 8083);
  print(
    'Try: curl -H "x-session-id: abc" http://127.0.0.1:8083/sessions/current',
  );
  print('Try: curl http://127.0.0.1:8083/users/1');
  print('Try: curl http://127.0.0.1:8083/users/999  # returns 404');
}
