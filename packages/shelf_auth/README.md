# shelf_auth

Shelf adapters for `server_auth`.

`shelf_auth` keeps the framework-specific wiring thin while reusing the
provider/contracts/runtime pieces from `server_auth`.

## Installation

```yaml
dependencies:
  shelf_auth: ^0.1.0
  server_auth: ^0.1.0
  shelf: ^1.4.2
```

## Features

- `bearerAuth` middleware to resolve bearer tokens into `AuthPrincipal`.
- `authProvidersEndpoint` middleware to expose `/auth/providers` metadata.
- `authPrincipal` helper to read resolved principal from request context.
- `bearerToken` helper to parse bearer token from request headers.
- `requireAuthenticated` and `requireRoles` middlewares for protected routes.

## When to Use

- Use `shelf_auth` when your server runtime is Shelf.
- Keep provider definitions, JWT helpers, and authorization contracts in
  `server_auth` so they remain portable.

## Quick Start

```dart
import 'dart:convert';

import 'package:server_auth/server_auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_auth/shelf_auth.dart';

Future<AuthPrincipal?> resolvePrincipal(String token, Request request) async {
  if (token != 'demo-token') return null;
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
        bearerAuth(
          resolvePrincipal: resolvePrincipal,
          strict: false,
        ),
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
  print('shelf_auth example listening on http://${server.address.host}:${server.port}');
}
```

Try:

```bash
curl -i http://127.0.0.1:8080/auth/providers
curl -i http://127.0.0.1:8080/me
curl -i -H "Authorization: Bearer demo-token" http://127.0.0.1:8080/me
```

## Strict vs Optional Bearer Auth

- `strict: false` lets anonymous requests continue when token is missing/invalid.
- `strict: true` returns `401` when token is missing/invalid.

Use `strict: false` when only some routes require auth and your handler checks
`authPrincipal(request)` explicitly.

## Route Guards

Use `requireAuthenticated` and `requireRoles` after principal resolution:

```dart
final protected = const Pipeline()
    .addMiddleware(
      bearerAuth(
        strict: false,
        resolvePrincipal: resolvePrincipal,
      ),
    )
    .addMiddleware(requireAuthenticated())
    .addMiddleware(requireRoles(<String>['admin']))
    .addHandler((_) => Response.ok('ok'));
```

## Custom Providers Endpoint Path

```dart
final middleware = authProvidersEndpoint(
  providers: providers,
  path: '/api/auth/providers',
);
```

## Runnable Example

```bash
dart run example/main.dart
```

## Migration Notes

If older code used Routed auth middleware only for bearer parsing or role
guards, move those routes to `shelf_auth` middleware and keep provider/runtime
logic in `server_auth`.
