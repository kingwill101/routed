import 'package:routed/routed.dart';
import 'package:routed_openapi/routed_openapi.dart';

void main() async {
  final engine = Engine();

  // Routes no longer carry RouteSchema directly on Router (moved to routed_openapi).
  // Define schemas separately and compose them via routed_openapi helpers.
  engine.get('/users', (ctx) async => ctx.response.json({'users': []}));
  engine.post('/users', (ctx) async => ctx.response.json({'created': true}));

  // Example schemas (can be attached via routed_openapi registry/middleware if needed)
  const listSchema = RouteSchema(summary: 'List users', tags: ['users']);
  const createSchema = RouteSchema(summary: 'Create user', tags: ['users']);

  // Build manifest
  final manifest = engine.buildRouteManifest();

  // Convert to OpenAPI
  final spec = manifestToOpenApi(manifest, config: const OpenApiConfig(title: 'User Service', version: '1.0.0'));
  print(spec.toJsonString(pretty: true));

  await engine.close();
}
