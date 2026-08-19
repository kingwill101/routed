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
  final client = http.Client();

  final jwtMiddleware = jwtAuthentication(
    JwtOptions(
      issuer: '$baseUrl/realms/$realm',
      audience: const ['account'],
      jwksUri: jwksUri,
      algorithms: const ['RS256'],
    ),
    httpClient: client,
  );
  final introspectionMiddleware = oauth2Introspection(
    OAuthIntrospectionOptions(
      endpoint: introspectionEndpoint,
      clientId: clientId,
      clientSecret: clientSecret,
      tokenTypeHint: 'access_token',
      cacheTtl: const Duration(seconds: 30),
    ),
    httpClient: client,
  );

  final engine = Engine(providers: Engine.defaultProviders);

  engine.get('/healthz', (ctx) => ctx.string('ok'));

  engine.get('/profile', (ctx) {
    final claims = ctx.get<Map<String, dynamic>>(jwtClaimsAttribute);
    if (claims == null) {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('missing token');
      return ctx.string('');
    }
    return ctx.json({'sub': claims['sub'], 'scope': claims['scope']});
  }, middlewares: [jwtMiddleware]);

  engine.get('/oauth-profile', (ctx) {
    final claims = ctx.get<Map<String, dynamic>>(oauthClaimsAttribute);
    if (claims == null) {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('missing token');
      return ctx.string('');
    }
    return ctx.json({'sub': claims['sub'], 'scope': claims['scope']});
  }, middlewares: [introspectionMiddleware]);

  engine.get('/call-client-credentials', (ctx) async {
    final oauthClient = OAuth2Client(
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      clientSecret: clientSecret,
      httpClient: client,
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
