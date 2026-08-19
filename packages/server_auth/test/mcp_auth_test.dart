import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'MCP metadata advertises protected resource and OAuth server contracts',
    () async {
      final feature = McpAuthFeature<Object>(
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
      () => McpAuthFeature<Object>(
        protectedResource: AuthOAuthProtectedResourceMetadata(
          resource: Uri.parse('/mcp'),
          authorizationServers: [Uri.parse('https://auth.example.test')],
        ),
        authorizationServer: _serverMetadata(),
      ),
      throwsArgumentError,
    );
    expect(
      () => McpAuthFeature<Object>(
        protectedResource: AuthOAuthProtectedResourceMetadata(
          resource: Uri.parse('https://mcp.example.test/mcp#fragment'),
          authorizationServers: [Uri.parse('https://auth.example.test')],
        ),
        authorizationServer: _serverMetadata(),
      ),
      throwsArgumentError,
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
