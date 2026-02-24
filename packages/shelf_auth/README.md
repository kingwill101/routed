# shelf_auth

Thin Shelf adapters for `server_auth`.

## Features

- `bearerAuth` middleware for resolving `Authorization: Bearer ...` tokens to `AuthPrincipal`.
- `authProvidersEndpoint` middleware to expose `/auth/providers` from configured `AuthProvider` values.
- `authPrincipal` and `bearerToken` helpers for request-level access.

## Usage

```dart
import 'package:server_auth/server_auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_auth/shelf_auth.dart';

final providers = <AuthProvider>[
  AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
];

final app = const Pipeline()
    .addMiddleware(
      bearerAuth(
        strict: true,
        resolvePrincipal: (token, _) async {
          if (token == 'demo-token') {
            return AuthPrincipal(id: 'user-1', roles: const <String>['user']);
          }
          return null;
        },
      ),
    )
    .addMiddleware(authProvidersEndpoint(providers: providers))
    .addHandler((request) {
      final principal = authPrincipal(request);
      return Response.ok(principal?.id ?? 'anonymous');
    });
```
