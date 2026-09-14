import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';

import 'migrations.dart';

const _noteColumns = <AdHocColumn>[
  AdHocColumn(
    name: 'id',
    dartType: 'int',
    columnType: 'INTEGER',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'title', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'body', dartType: 'String', isNullable: false),
];

/// Builds a normal VM/Node-style Routed app.
Future<Engine> createEngine({
  String databasePath = 'storage/app.sqlite',
}) async {
  final databases = DatabaseManager()
    ..registerFactory(
      'default',
      () => SqliteDatabase.connect(path: databasePath),
    );

  final engine = Engine(
    providers: <ServiceProvider>[
      ...Engine.defaultProviders,
      RoutedDatabaseProvider(
        manager: databases,
        migrations: appMigrations,
        migrateOnBoot: true,
      ),
    ],
  );

  engine.get('/health', (ctx) {
    return ctx.json({
      'ok': true,
      'database': ctx.db().driver.runtimeType.toString(),
    });
  });

  engine.get('/api/notes', (ctx) async {
    final rows = await _notes(ctx.db()).orderBy('id').get();
    return ctx.json({'data': rows});
  });

  engine.post('/api/notes', (ctx) async {
    final payload = Map<String, dynamic>.from(
      await ctx.bindJSON({}) as Map? ?? const {},
    );
    final title = payload['title']?.toString().trim() ?? '';
    final body = payload['body']?.toString() ?? '';
    if (title.isEmpty) {
      return ctx.json({
        'error': 'title_required',
      }, statusCode: HttpStatus.unprocessableEntity);
    }
    await _notes(ctx.db()).insertManyInputs([
      {'title': title, 'body': body},
    ], returning: false);
    return ctx.json({'created': true}, statusCode: HttpStatus.created);
  });

  await engine.initialize();
  return engine;
}

Query<AdHocRow> _notes(OrmDatabase database) =>
    database.table('notes', columns: _noteColumns);
