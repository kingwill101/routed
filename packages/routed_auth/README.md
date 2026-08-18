# routed_auth

Routed-specific auth integration on top of `server_auth`.

This package contains the HTTP/session/router glue for auth in Routed:

- `AuthServiceProvider`
- `AuthRoutes`
- `AuthManager`
- `SessionAuth` + guard middleware
- Routed JWT/OAuth middleware wrappers
- Haigate middleware bridge

Use this when you want auth routes and middleware in a Routed app.

## Install

```yaml
dependencies:
  routed: ^0.4.0
  server_auth: ^0.1.0
  routed_auth: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:server_auth/server_auth.dart';

void main() async {
  registerRoutedProviders();
  // Engine.create initializes routed.auth and the other official providers.
  final engine = await Engine.create();

  // Example runtime options.
  engine.instance<AuthOptions<EngineContext>>(
    AuthOptions<EngineContext>(
      adapter: AuthAdapter(),
      providers: const <AuthProvider>[],
    ),
  );

  engine.get(
    '/account',
    (ctx) => ctx.json({'authenticated': true}),
    middlewares: [requireAuthenticated()],
  );

  await engine.serve(port: 8080);
}
```

For a slim composition, import `routed_auth` directly and add
`AuthServiceProvider()` after `Engine.defaultProviders`. Call
`registerRoutedAuthProviders()` first if your configuration manifest names
`routed.auth` and you are not importing the `routed` facade.
