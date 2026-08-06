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
  routed: ^0.3.3
  server_auth: ^0.1.0
  routed_auth: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:server_auth/server_auth.dart';

void main() async {
  final engine = Engine.createSync();

  // Needed when loading providers from config manifests that reference routed.auth.
  ensureRoutedAuthProviderRegistered();

  engine.registerProvider(AuthServiceProvider());

  // Example runtime options.
  engine.instance<AuthOptions<EngineContext>>(
    AuthOptions<EngineContext>(
      adapter: AuthAdapter(),
      providers: const <AuthProvider>[],
    ),
  );
}
```
