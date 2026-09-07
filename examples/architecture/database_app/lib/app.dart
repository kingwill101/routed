import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';

import 'migrations.dart';

/// Builds a normal VM/Node-style Routed app.
Future<Engine> createEngine({String databasePath = ':memory:'}) async {
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
    final rows = await ctx.db().queryRaw(
      'SELECT id, title, body FROM notes ORDER BY id',
    );
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
    await ctx.db().executeRaw('INSERT INTO notes (title, body) VALUES (?, ?)', [
      title,
      body,
    ]);
    return ctx.json({'created': true}, statusCode: HttpStatus.created);
  });

  await engine.initialize();
  return engine;
}
