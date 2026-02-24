import 'dart:convert';

import 'package:server_auth/server_auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_auth/shelf_auth.dart';

Future<AuthPrincipal?> resolvePrincipal(String token, Request request) async {
  if (token != 'demo-token') {
    return null;
  }
  return AuthPrincipal(
    id: 'user-1',
    roles: <String>['user'],
    attributes: <String, dynamic>{'plan': 'pro'},
  );
}

Future<void> main() async {
  final providers = <AuthProvider>[
    const AuthProvider(
      id: 'google',
      name: 'Google',
      type: AuthProviderType.oidc,
    ),
    const AuthProvider(
      id: 'credentials',
      name: 'Credentials',
      type: AuthProviderType.credentials,
    ),
  ];

  final handler = const Pipeline()
      .addMiddleware(
        bearerAuth(resolvePrincipal: resolvePrincipal, strict: false),
      )
      .addMiddleware(authProvidersEndpoint(providers: providers))
      .addHandler((request) {
        if (request.url.path == 'me') {
          final principal = authPrincipal(request);
          if (principal == null) {
            return Response.unauthorized(
              jsonEncode(<String, String>{'error': 'unauthenticated'}),
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return Response.ok(
            jsonEncode(<String, Object?>{
              'id': principal.id,
              'roles': principal.roles,
              'attributes': principal.attributes,
            }),
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return Response.notFound('Not Found');
      });

  final server = await shelf_io.serve(handler, '127.0.0.1', 8080);
  print(
    'shelf_auth example listening on http://${server.address.host}:${server.port}',
  );
}
