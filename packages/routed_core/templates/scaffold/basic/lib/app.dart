import 'package:routed_core/routed_core.dart';
import 'package:routed_database/routed_database.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  final engine = Engine(
    providers: [
      CoreServiceProvider(),
      RoutingServiceProvider(),
    ],
  );

  if (initialize) {
    await engine.initialize();
  }

  engine.get('/db/health', (ctx) async {
    final rows = await ctx.db().queryRaw(
      'SELECT COUNT(*) AS count FROM orm_migrations',
    );
    return ctx.json({
      'ok': true,
      'migrations': rows.isEmpty ? 0 : rows.first['count'],
    });
  });

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to {{{routed:humanName}}}!'});
  });

  return engine;
}
