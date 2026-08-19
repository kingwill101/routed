import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test('MCP metadata is published at standard root well-known paths', () async {
    final feature = McpAuthFeature<EngineContext>(
      protectedResource: AuthOAuthProtectedResourceMetadata(
        resource: Uri.parse('https://mcp.example.test/mcp'),
        authorizationServers: [Uri.parse('https://auth.example.test')],
      ),
      authorizationServer: AuthOAuthAuthorizationServerMetadata(
        issuer: Uri.parse('https://auth.example.test'),
        authorizationEndpoint: Uri.parse(
          'https://auth.example.test/oauth/authorize',
        ),
        tokenEndpoint: Uri.parse('https://auth.example.test/oauth/token'),
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: const [],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        features: [feature],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final protectedResource = await client.get(
      '/.well-known/oauth-protected-resource',
    );
    protectedResource.assertStatus(HttpStatus.ok);
    expect(
      protectedResource.json()['resource'],
      'https://mcp.example.test/mcp',
    );
    expect(protectedResource.json()['authorization_servers'], [
      'https://auth.example.test',
    ]);

    final server = await client.get('/.well-known/oauth-authorization-server');
    server.assertStatus(HttpStatus.ok);
    expect(server.json()['issuer'], 'https://auth.example.test');
  });
}
