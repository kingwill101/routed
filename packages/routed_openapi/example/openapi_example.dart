import 'package:routed_core/routed_core.dart';
import 'package:routed_openapi/routed_openapi.dart';

void main() async {
  final engine = Engine();

  const listSchema = RouteSchema(summary: 'List users', tags: ['users']);
  const createSchema = RouteSchema(summary: 'Create user', tags: ['users']);

  engine
      .get('/users', (ctx) async => ctx.response.json({'users': []}))
      .schema(listSchema);
  engine
      .post('/users', (ctx) async => ctx.response.json({'created': true}))
      .schema(createSchema);

  // Build manifest
  final manifest = engine.buildRouteManifest();

  // Convert to OpenAPI
  final spec = manifestToOpenApi(
    manifest,
    config: const OpenApiConfig(title: 'User Service', version: '1.0.0'),
  );
  print(spec.toJsonString(pretty: true));

  await engine.close();
}
