import 'package:routed/routed.dart';

import 'config.dart';
import 'platform/platform_config.dart';
import 'platform/platform_runtime.dart';

Future<Engine> createEngine() async {
  final setup = config();
  final engine = await Engine.create(providers: setup.providers);

  engine.get('/health', (ctx) async => ctx.json({'status': 'ok'}));

  engine.post('/v1/tasks', (ctx) async {
    final auth = _authenticate(ctx);
    if (auth == null) return _unauthorized(ctx);

    final idempotencyKey = ctx.requestHeader('Idempotency-Key')?.trim();
    if (idempotencyKey == null || idempotencyKey.isEmpty) {
      return ctx.json({
        'error': 'Idempotency-Key is required',
      }, statusCode: HttpStatus.badRequest);
    }

    final body = Map<String, dynamic>.from(
      await ctx.bindJSON({}) as Map? ?? const {},
    );
    final message = body['message']?.toString().trim() ?? '';
    if (message.isEmpty) {
      return ctx.json({
        'error': 'message is required',
      }, statusCode: HttpStatus.unprocessableEntity);
    }

    try {
      final runtime = await ctx.container.make<PlatformRuntime>();
      final task = await runtime.submit(
        tenant: auth.tenant,
        namespace: auth.namespace,
        idempotencyKey: idempotencyKey,
        message: message,
      );
      return ctx.json({
        'taskId': task.id,
        'accepted': true,
      }, statusCode: HttpStatus.accepted);
    } on StateError catch (error) {
      return ctx.json({
        'error': error.message,
      }, statusCode: HttpStatus.conflict);
    }
  });

  engine.get('/v1/tasks/{taskId}', (ctx) async {
    final auth = _authenticate(ctx);
    if (auth == null) return _unauthorized(ctx);

    final taskId = ctx.mustGetParam<String>('taskId');
    final runtime = await ctx.container.make<PlatformRuntime>();
    final status = await runtime.status(
      tenant: auth.tenant,
      namespace: auth.namespace,
      taskId: taskId,
    );
    if (status == null) {
      return ctx.json({
        'error': 'Task not found',
      }, statusCode: HttpStatus.notFound);
    }
    return ctx.json(status);
  });

  return engine;
}

_Auth? _authenticate(EngineContext ctx) {
  final token = ctx.requestHeader(HttpHeaders.authorizationHeader);
  final configuration = ctx.container.get<PlatformConfig>();
  if (token != 'Bearer ${configuration.apiToken}') {
    return null;
  }
  final namespace =
      ctx.requestHeader('X-Routed-Namespace') ?? configuration.defaultNamespace;
  return _Auth(tenant: configuration.defaultTenant, namespace: namespace);
}

Response _unauthorized(EngineContext ctx) =>
    ctx.json({'error': 'Unauthorized'}, statusCode: HttpStatus.unauthorized);

final class _Auth {
  const _Auth({required this.tenant, required this.namespace});

  final String tenant;
  final String namespace;
}
