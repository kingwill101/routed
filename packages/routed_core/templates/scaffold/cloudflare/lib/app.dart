import 'package:routed_core/routed_core.dart';
import 'package:routed_database/routed_database.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/cli_provider.dart';
import 'package:routed_sessions/routed_sessions.dart';

/// Builds the environment-backed Cloudflare Worker engine.
Future<Engine> createCloudflareEngine(
  CloudflareEnvironment environment, {
  bool initialize = true,
}) async {
  final setup = await config(environment);
  final engine = Engine(
    config: setup.engineConfig,
    options: setup.options,
    providers: setup.providers,
  );

  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  if (initialize) {
    await engine.initialize();
  }

  _registerRoutes(engine);
  return engine;
}

/// Keeps CLI route inspection and local compilation side-effect free.
Future<Engine> createEngine({bool initialize = true}) async {
  final engine = Engine(
    providers: [
      CoreServiceProvider(),
      RoutingServiceProvider(),
      ...routedNodeCliProviders(),
    ],
  );

  if (initialize) {
    await engine.initialize();
  }

  _registerRoutes(engine);
  return engine;
}

void _registerRoutes(Engine engine) {
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
    return ctx.json({
      'service': '{{{routed:packageName}}}',
      'runtime': 'cloudflare',
      'message': 'Routed Cloudflare Worker',
    });
  });
}
