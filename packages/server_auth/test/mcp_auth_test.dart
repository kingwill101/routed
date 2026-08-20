import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'MCP metadata advertises protected resource and OAuth server contracts',
    () async {
      final feature = McpAuthPlugin<Object>(
        protectedResource: AuthOAuthProtectedResourceMetadata(
          resource: Uri.parse('https://mcp.example.test/mcp'),
          authorizationServers: [Uri.parse('https://auth.example.test')],
          resourceName: 'Example MCP',
          scopesSupported: const ['mcp:read', 'mcp:write'],
        ),
        authorizationServer: AuthOAuthAuthorizationServerMetadata(
          issuer: Uri.parse('https://auth.example.test'),
          authorizationEndpoint: Uri.parse(
            'https://auth.example.test/oauth/authorize',
          ),
          tokenEndpoint: Uri.parse('https://auth.example.test/oauth/token'),
          registrationEndpoint: Uri.parse(
            'https://auth.example.test/oauth/register',
          ),
          scopesSupported: const ['mcp:read', 'mcp:write'],
        ),
      );

      final protectedEndpoint = feature.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'mcpAuth.protectedResourceMetadata',
      );
      final protectedPayload = Map<String, dynamic>.from(
        await protectedEndpoint.invoke(
              const AuthOperationInvocation<Object>(
                context: Object(),
                user: null,
              ),
              const <String, dynamic>{},
            )
            as Map,
      );
      expect(protectedPayload['resource'], 'https://mcp.example.test/mcp');
      expect(protectedPayload['authorization_servers'], [
        'https://auth.example.test',
      ]);
      expect(protectedPayload['scopes_supported'], ['mcp:read', 'mcp:write']);

      final serverEndpoint = feature.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'mcpAuth.authorizationServerMetadata',
      );
      final serverPayload = Map<String, dynamic>.from(
        await serverEndpoint.invoke(
              const AuthOperationInvocation<Object>(
                context: Object(),
                user: null,
              ),
              const <String, dynamic>{},
            )
            as Map,
      );
      expect(serverPayload['issuer'], 'https://auth.example.test');
      expect(serverPayload['code_challenge_methods_supported'], ['S256']);
    },
  );

  test('MCP metadata rejects relative and fragment-bearing URIs', () {
    expect(
      () => McpAuthPlugin<Object>(
        protectedResource: AuthOAuthProtectedResourceMetadata(
          resource: Uri.parse('/mcp'),
          authorizationServers: [Uri.parse('https://auth.example.test')],
        ),
        authorizationServer: _serverMetadata(),
      ),
      throwsArgumentError,
    );
    expect(
      () => McpAuthPlugin<Object>(
        protectedResource: AuthOAuthProtectedResourceMetadata(
          resource: Uri.parse('https://mcp.example.test/mcp#fragment'),
          authorizationServers: [Uri.parse('https://auth.example.test')],
        ),
        authorizationServer: _serverMetadata(),
      ),
      throwsArgumentError,
    );
  });

  test('dynamic client registration delegates validated requests', () async {
    AuthOAuthClientRegistrationRequest? captured;
    final feature = McpAuthPlugin<String>(
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
          'https://auth.example.test/oauth/register',
        ),
      ),
      registerClient: (context, request) {
        expect(context, 'request-context');
        captured = request;
        return AuthOAuthClientRegistration(
          clientId: 'client-1',
          redirectUris: request.redirectUris,
          grantTypes: request.grantTypes,
          responseTypes: request.responseTypes,
          tokenEndpointAuthMethod: request.tokenEndpointAuthMethod,
          clientName: request.clientName,
        );
      },
    );

    final endpoint = feature.endpoints.singleWhere(
      (endpoint) => endpoint.id == 'mcpAuth.registerClient',
    );
    final payload = Map<String, dynamic>.from(
      await endpoint.invoke(
            const AuthOperationInvocation<String>(
              context: 'request-context',
              user: null,
            ),
            const <String, dynamic>{
              'client_name': 'Example MCP client',
              'redirect_uris': ['https://client.example/callback'],
              'grant_types': ['authorization_code'],
              'response_types': ['code'],
              'token_endpoint_auth_method': 'none',
              'scope': 'mcp:read',
            },
          )
          as Map,
    );

    expect(captured?.clientName, 'Example MCP client');
    expect(captured?.redirectUris, [
      Uri.parse('https://client.example/callback'),
    ]);
    expect(captured?.scope, 'mcp:read');
    expect(payload['client_id'], 'client-1');
    expect(payload['redirect_uris'], ['https://client.example/callback']);
    expect(feature.clientOperations.single.serverOnly, isTrue);
    expect(
      endpoint.rateLimitOperation,
      const AuthRateLimitOperation('mcp_auth', 'register_client'),
    );
    expect(feature.rateLimitOperations, contains(endpoint.rateLimitOperation));
  });

  test('dynamic client registration rejects unsafe clients', () async {
    final feature = McpAuthPlugin<Object>(
      protectedResource: AuthOAuthProtectedResourceMetadata(
        resource: Uri.parse('https://mcp.example.test/mcp'),
        authorizationServers: [Uri.parse('https://auth.example.test')],
      ),
      authorizationServer: _serverMetadata(),
      registerClient: (_, _) => AuthOAuthClientRegistration(
        clientId: 'unused',
        redirectUris: [Uri.parse('https://client.example/callback')],
        grantTypes: ['authorization_code'],
        responseTypes: ['code'],
        tokenEndpointAuthMethod: 'none',
      ),
    );
    final endpoint = feature.endpoints.singleWhere(
      (endpoint) => endpoint.id == 'mcpAuth.registerClient',
    );

    Future<Object?> invoke(Map<String, dynamic> input) async => endpoint.invoke(
      const AuthOperationInvocation<Object>(context: Object(), user: null),
      input,
    );

    await expectLater(
      invoke({
        'redirect_uris': ['http://client.example/callback'],
      }),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'invalid_redirect_uris',
        ),
      ),
    );
    await expectLater(
      invoke({
        'redirect_uris': ['http://localhost:3000/callback'],
        'token_endpoint_auth_method': 'client_secret_basic',
      }),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'unsupported_token_endpoint_auth_method',
        ),
      ),
    );
    await expectLater(
      invoke({
        'redirect_uris': ['http://localhost:3000/callback'],
        'grant_types': ['client_credentials'],
      }),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'unsupported_client_configuration',
        ),
      ),
    );
  });

  test('OAuth introspection enforces configured token audience', () async {
    final introspector = OAuth2TokenIntrospector(
      OAuthIntrospectionOptions(
        endpoint: Uri.parse('https://auth.example.test/introspect'),
        requiredAudience: 'https://mcp.example.test/mcp',
      ),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'active': true,
            'aud': ['https://other.example.test'],
            'exp':
                DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
          200,
        ),
      ),
    );

    await expectLater(
      introspector.validate('token-1'),
      throwsA(isA<OAuth2Exception>()),
    );
  });
}

AuthOAuthAuthorizationServerMetadata _serverMetadata() =>
    AuthOAuthAuthorizationServerMetadata(
      issuer: Uri.parse('https://auth.example.test'),
      authorizationEndpoint: Uri.parse(
        'https://auth.example.test/oauth/authorize',
      ),
      tokenEndpoint: Uri.parse('https://auth.example.test/oauth/token'),
    );
