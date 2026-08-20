import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test('MCP metadata is published at standard root well-known paths', () async {
    final feature = McpAuthPlugin<EngineContext>(
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
        plugins: [feature],
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

  test(
    'MCP dynamic client registration is mounted under the auth base path',
    () async {
      final feature = McpAuthPlugin<EngineContext>(
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
          registrationEndpoint: Uri.parse(
            'https://auth.example.test/auth/oauth/register',
          ),
        ),
        registerClient: (_, request) => AuthOAuthClientRegistration(
          clientId: 'mcp-client-1',
          clientName: request.clientName,
          redirectUris: request.redirectUris,
          grantTypes: request.grantTypes,
          responseTypes: request.responseTypes,
          tokenEndpointAuthMethod: request.tokenEndpointAuthMethod,
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: const [],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      final engine = testEngine();
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final response = await client.postJson('/auth/oauth/register', {
        'client_name': 'MCP client',
        'redirect_uris': ['https://client.example/callback'],
      });
      response.assertStatus(HttpStatus.ok);
      expect(response.json()['client_id'], 'mcp-client-1');
      expect(response.json()['client_name'], 'MCP client');
    },
  );

  test('feature redirects are emitted as HTTP redirects by Routed', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: const [],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: [_RedirectPlugin()],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final response = await client.get('/auth/redirect');
    response.assertStatus(HttpStatus.found);
    expect(response.headers['location'], ['https://client.example/callback']);
  });

  test('well-known metadata resolves the live manager after reload', () async {
    AuthManager buildManager(String host) => AuthManager(
      AuthOptions<EngineContext>(
        providers: const [],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: [
          McpAuthPlugin<EngineContext>(
            protectedResource: AuthOAuthProtectedResourceMetadata(
              resource: Uri.parse('https://mcp.example.test/mcp'),
              authorizationServers: [Uri.parse('https://$host')],
            ),
            authorizationServer: AuthOAuthAuthorizationServerMetadata(
              issuer: Uri.parse('https://$host'),
              authorizationEndpoint: Uri.parse('https://$host/oauth/authorize'),
              tokenEndpoint: Uri.parse('https://$host/oauth/token'),
            ),
          ),
        ],
      ),
    );

    final initial = buildManager('old-auth.example.test');
    var live = initial;
    final engine = testEngine();
    AuthRoutes(initial, managerOf: () => live).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    live = buildManager('new-auth.example.test');
    final response = await client.get(
      '/.well-known/oauth-authorization-server',
    );

    response.assertStatus(HttpStatus.ok);
    expect(response.json()['issuer'], 'https://new-auth.example.test');
    expect(
      response.json()['token_endpoint'],
      'https://new-auth.example.test/oauth/token',
    );
  });

  test('Routed preserves path, query, and body namespaces', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: const [],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: const <AuthServerPlugin<EngineContext>>[_NamespacePlugin()],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final response = await client.postJson(
      '/auth/namespaces/a%2Fb%20%3F%23%25%3Fid=query?id=query&query=visible',
      <String, dynamic>{'id': 'body', 'value': 'payload'},
    );

    response.assertStatus(HttpStatus.ok);
    expect(response.json(), <String, dynamic>{
      'path': 'a/b ?#%?id=query',
      'query': <String, dynamic>{'id': 'query', 'query': 'visible'},
      'body': <String, dynamic>{'id': 'body', 'value': 'payload'},
    });
  });
}

const AuthRouteParameterKey _namespaceId = AuthRouteParameterKey('id');

final class _NamespacePlugin
    implements
        AuthServerPlugin<EngineContext>,
        AuthEndpointContributor<EngineContext> {
  const _NamespacePlugin();

  @override
  String get id => 'namespace-test';

  @override
  void configure(AuthServerPluginContext<EngineContext> context) {}

  @override
  Iterable<AuthEndpointDescriptor<EngineContext>> get endpoints => [
    TypedAuthEndpointDescriptor<EngineContext, Map<String, dynamic>, Object?>(
      id: 'namespace-test.echo',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath(
        '/namespaces/{id}',
        parameters: <AuthRouteParameterKey>[_namespaceId],
      ),
      semantics: const AuthOperationSemantics.readOnly(),
      requestCodec: AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      responseCodec: AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      handler: (invocation, body) => <String, dynamic>{
        'path': invocation.request.requirePath(_namespaceId),
        'query': invocation.request.query,
        'body': body,
      },
    ),
  ];
}

final class _RedirectPlugin
    implements
        AuthServerPlugin<EngineContext>,
        AuthEndpointContributor<EngineContext> {
  @override
  String get id => 'redirect-test';

  @override
  void configure(AuthServerPluginContext<EngineContext> context) {}

  @override
  Iterable<AuthEndpointDescriptor<EngineContext>> get endpoints => [
    TypedAuthEndpointDescriptor<EngineContext, Map<String, dynamic>, Object?>(
      id: 'redirect-test.endpoint',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/redirect'),
      semantics: const AuthOperationSemantics.readOnly(),
      requestCodec: AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      responseCodec: AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      handler: (_, _) => AuthEndpointRedirect(
        location: Uri.parse('https://client.example/callback'),
      ),
    ),
  ];
}
