import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/routed.dart';

Future<void> main() async {
  final baseUrl =
      Platform.environment['KEYCLOAK_BASE_URL'] ?? 'http://localhost:8081';
  final realm = Platform.environment['KEYCLOAK_REALM'] ?? 'demo';
  final clientId =
      Platform.environment['KEYCLOAK_CLIENT_ID'] ?? 'routed-resource';
  final clientSecret =
      Platform.environment['KEYCLOAK_CLIENT_SECRET'] ?? 'secret';

  final tokenEndpoint = Uri.parse(
    '$baseUrl/realms/$realm/protocol/openid-connect/token',
  );
  final jwksUri = Uri.parse(
    '$baseUrl/realms/$realm/protocol/openid-connect/certs',
  );
  final introspectionEndpoint = Uri.parse(
    '$baseUrl/realms/$realm/protocol/openid-connect/token/introspect',
  );

  final engine = Engine(
    configItems: {
      'http': {
        'features': {
          'auth': {'enabled': true},
        },
      },
      'auth': {
        'oauth2': {
          'introspection': {
            'enabled': true,
            'endpoint': introspectionEndpoint.toString(),
            'client_id': clientId,
            'client_secret': clientSecret,
            'token_type_hint': 'access_token',
            'cache_ttl': '30s',
          },
        },
        'jwt': {
          'enabled': true,
          'issuer': '$baseUrl/realms/$realm',
          'audience': ['account'],
          'jwks_url': jwksUri.toString(),
          'algorithms': ['RS256'],
        },
      },
    },
  );

  engine.get('/healthz', (ctx) => ctx.string('ok'));

  engine.get('/profile', (ctx) {
    final claims =
        ctx.request.getAttribute<Map<String, dynamic>>(jwtClaimsAttribute) ??
        ctx.request.getAttribute<Map<String, dynamic>>(oauthClaimsAttribute);
    if (claims == null) {
      ctx.response.statusCode = HttpStatus.unauthorized;
      ctx.response.write('missing token');
      return ctx.response;
    }
    return ctx.json({'sub': claims['sub'], 'scope': claims['scope']});
  });

  engine.get('/call-client-credentials', (ctx) async {
    final oauthClient = OAuth2Client(
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      clientSecret: clientSecret,
      httpClient: http.Client(),
    );

    final tokenResponse = await oauthClient.clientCredentials(scope: 'profile');
    ctx.set(oauthTokenAttribute, tokenResponse.accessToken);
    ctx.set(oauthScopeAttribute, tokenResponse.scope);

    return ctx.json({
      'access_token': tokenResponse.accessToken,
      'expires_in': tokenResponse.expiresIn,
      'scope': tokenResponse.scope,
    });
  });

  await engine.initialize();
  await engine.serve(host: '0.0.0.0', port: 8080);
}
