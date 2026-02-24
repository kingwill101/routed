# server_auth

Framework-agnostic authentication runtime primitives and provider implementations.

Includes built-in providers for Google, Discord, Microsoft Entra, Apple, Twitter/X,
Facebook, GitLab, Slack, Spotify, LinkedIn, Twitch, Dropbox, and Telegram.

`server_auth` is designed to be consumed by framework adapters. It provides auth
building blocks (providers, JWT, CSRF, gates/authorization, callbacks, token
utilities) without requiring Routed-specific runtime types.

## Installation

```yaml
dependencies:
  server_auth: ^0.1.0
```

## Entry points

- `package:server_auth/server_auth.dart` (umbrella export)
- `package:server_auth/src/core/*` (advanced, package-internal structure)

## Package Selection

- Use `server_auth` for auth runtime primitives and provider implementations.
- Use `server_contracts` for contract-only abstractions.
- Use adapter packages (`routed`, `shelf_auth`, etc.) for framework-specific HTTP/session wiring.

## Quick start

```dart
import 'package:server_auth/server_auth.dart';

final registry = AuthProviderRegistry.instance;
registerAllAuthProviders(registry);

final google = googleProvider(
  GoogleProviderOptions(
    clientId: 'google-client-id',
    clientSecret: 'google-client-secret',
    redirectUri: 'https://example.com/auth/callback/google',
  ),
);

final providers = <AuthProvider>[google];
```

Use `providers` with your framework adapter to wire callback routes, session
handling, and auth lifecycle.

## Using with Shelf

Use `shelf_auth` for Shelf-specific middleware while keeping providers and
auth contracts in `server_auth`.

```yaml
dependencies:
  server_auth: ^0.1.0
  shelf_auth: ^0.1.0
```

```dart
import 'package:server_auth/server_auth.dart';
import 'package:shelf_auth/shelf_auth.dart';

final providers = <AuthProvider>[
  const AuthProvider(
    id: 'credentials',
    name: 'Credentials',
    type: AuthProviderType.credentials,
  ),
];

final middleware = authProvidersEndpoint(providers: providers);
```

## Config-Driven Registration

```dart
import 'package:server_auth/server_auth.dart';

registerAllAuthProviders(AuthProviderRegistry.instance);
```

Then map framework config into provider options and resolve providers from the
registry by key.

## JWT issue + verify example

```dart
import 'package:server_auth/server_auth.dart';

final options = const JwtSessionOptions(
  secret: 'replace-with-a-strong-secret',
  issuer: 'example-app',
  audience: <String>['example-api'],
  maxAge: Duration(minutes: 30),
);

final issued = issueAuthJwtToken(
  options: options,
  claims: <String, dynamic>{'sub': 'user_42', 'roles': <String>['admin']},
);

final verifier = JwtVerifier(options: options.toVerifierOptions());
final payload = await verifier.verifyToken(issued.token);
print(payload.subject);
```

## Adapter attribute mapping helpers

When writing framework adapters, use these helpers to store verified auth
payloads with consistent attribute keys:

```dart
import 'package:server_auth/server_auth.dart';

final attributes = <String, Object?>{};

writeJwtPayloadAttributes(
  payload,
  setAttribute: (key, value) => attributes[key] = value,
);

writeOAuthValidationAttributes(
  oauthValidation,
  setAttribute: (key, value) => attributes[key] = value,
);
```

## Authorization and gates example

```dart
import 'package:server_auth/server_auth.dart';

final gates = AuthGateService<Map<String, dynamic>>();
gates.register('posts.update', rolesGate(<String>['editor', 'admin'], any: true));

final principal = AuthPrincipal(id: 'user_42', roles: <String>['admin']);
final allowed = await gates.can(
  'posts.update',
  context: <String, dynamic>{'resourceId': 'post_1'},
  principal: principal,
);
print(allowed); // true
```

## Framework Adapter Session Runtime

`RememberSessionAuthRuntime<TContext>` provides framework-agnostic
remember-me/session principal logic. Frameworks supply an
`AuthSessionRuntimeAdapter<TContext>` to map request/session/cookie behavior.

```dart
import 'package:server_auth/server_auth.dart';

final runtime = RememberSessionAuthRuntime<MyContext>(
  adapter: myAdapter,
  rememberCookieName: 'remember_token',
  defaultRememberDuration: const Duration(days: 30),
  sessionPrincipalKey: '__auth.principal',
);

await runtime.login(
  context,
  AuthPrincipal(id: 'user-1', roles: const <String>['user']),
  rememberMe: true,
);

await runtime.hydrate(context); // restore/rotate remember token when needed
await runtime.logout(context);
```

## Typed Profiles

Every OAuth provider includes a typed profile model and serializer/parsers,
so user info mapping can stay type-safe.

## Telegram (Non-OAuth)

Telegram uses widget-based auth with HMAC verification via `telegramProvider`.

## Runnable example

```bash
dart run example/main.dart
```

See `example/main.dart` for provider registration, JWT flows, and gate checks.

## Migration Notes

If older code imported provider factories or auth primitives from Routed
entrypoints, switch to direct `server_auth` imports to keep auth logic reusable
across frameworks.

## License

MIT
