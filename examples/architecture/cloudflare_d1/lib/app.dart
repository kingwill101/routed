import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';
import 'package:routed_node/cloudflare.dart';

import 'migrations.dart';

/// Builds the Worker application from its typed Cloudflare environment.
Future<Engine> createEngine(CloudflareEnvironment environment) async {
  final databases = DatabaseManager()
    ..registerFactory(
      'default',
      () => openCloudflareD1(environment, binding: 'DB'),
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
      'runtime': 'cloudflare',
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
    if (title.isEmpty) {
      return ctx.json({'error': 'title_required'}, statusCode: 422);
    }
    await ctx.db().executeRaw('INSERT INTO notes (title, body) VALUES (?, ?)', [
      title,
      payload['body']?.toString() ?? '',
    ]);
    return ctx.json({'created': true}, statusCode: 201);
  });

  await engine.initialize();
  return engine;
}
