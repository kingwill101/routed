import 'dart:async';
import 'dart:convert';

import 'package:jose/jose.dart';
import 'package:routed/routed.dart';

const _sharedSecret = 'demo-jwt-secret-key';

Map<String, dynamic> get _inlineHmacKey => <String, dynamic>{
  'kty': 'oct',
  'kid': 'inline-hmac',
  'alg': 'HS256',
  'k': base64UrlEncode(utf8.encode(_sharedSecret)).replaceAll('=', ''),
};

Future<void> main() async {
  final engine = Engine(
    providers: [
      CoreServiceProvider(
        configItems: {
          'security': {
            'ip_filter': {
              'enabled': true,
              'default_action': 'deny',
              'allow': ['127.0.0.1/32', '::1/128'],
              'deny': ['0.0.0.0/0'],
              'respect_trusted_proxies': false,
            },
          },
        },
      ),
      RoutingServiceProvider(),
    ],
  );

  engine.addGlobalMiddleware(
    jwtAuthentication(
      JwtOptions(
        issuer: 'https://auth.local',
        audience: const ['example-api'],
        inlineKeys: [_inlineHmacKey],
        algorithms: const ['HS256'],
      ),
      onVerified: (payload, ctx) {
        if (!(payload.claims['scope'] as String).contains('profile:read')) {
          throw JwtAuthException('insufficient_scope');
        }
        ctx.set('user', payload.claims['sub']);
      },
    ),
  );

  engine.get('/profile', (ctx) {
    final claims = ctx.get<Map<String, dynamic>>(jwtClaimsAttribute);
    final user = ctx.get<String>('user');
    if (claims == null || user == null) {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('missing token');
      return ctx.string('');
    }
    return ctx.json({'sub': user, 'scope': claims['scope']});
  });

  await engine.initialize();

  final token = _buildToken(scope: 'profile:read');
  print('Example bearer token (valid for 5 minutes):\n$token\n');
  print('curl -H "Authorization: Bearer $token" http://localhost:8080/profile');

  await engine.serve(host: 'localhost', port: 8080);
}

String _buildToken({required String scope}) {
  final now = DateTime.now().toUtc();
  final claims = <String, dynamic>{
    'sub': 'user-42',
    'iss': 'https://auth.local',
    'aud': ['example-api'],
    'scope': scope,
    'iat': _asSeconds(now),
    'nbf': _asSeconds(now.subtract(const Duration(seconds: 5))),
    'exp': _asSeconds(now.add(const Duration(minutes: 5))),
  };

  final builder = JsonWebSignatureBuilder()
    ..jsonContent = claims
    ..setProtectedHeader('alg', 'HS256')
    ..setProtectedHeader('typ', 'JWT')
    ..addRecipient(JsonWebKey.fromJson(_inlineHmacKey), algorithm: 'HS256');

  return builder.build().toCompactSerialization();
}

int _asSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
