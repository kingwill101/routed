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

Avoid `package:server_auth/src/*` imports from outside this package. The
public API is exposed through `server_auth.dart`.

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

final refreshed = await refreshAuthJwtTokenIfNeeded(
  options: options,
  claims: payload.claims,
  updateAge: const Duration(minutes: 15),
  resolveClaims: (claims) => claims,
);
```

## OAuth callback orchestration helper

Use `resolveOAuthSignInForProvider` in framework adapters to share OAuth
callback exchange/profile/user resolution logic without depending on Routed.

```dart
final resolved = await resolveOAuthSignInForProvider<MyContext, Map<String, dynamic>>(
  adapter: adapter,
  context: context,
  provider: oauthProvider,
  code: authorizationCode,
  codeVerifier: pkceVerifier,
  httpClient: httpClient,
);

await adapter.linkAccount(resolved.account);
print(resolved.user.id);
print(resolved.profile);
```

Use `resolveOAuthAuthorizationStart` to share OAuth begin-flow state/PKCE/callback
session persistence:

```dart
final start = await resolveOAuthAuthorizationStart<MyContext, Map<String, dynamic>>(
  context: context,
  provider: oauthProvider,
  stateKey: '_auth.state',
  pkceKey: '_auth.pkce',
  callbackKey: '_auth.callback',
  callbackUrl: '/dashboard',
  writeSession: (key, value) => sessionStore[key] = value,
);

return start.authorizationUri;
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

final callbackUrl = resolveAndSanitizeRedirectCandidate(
  payload,
  queryParameters,
  requestUri: requestUri,
  fallbackHost: 'app.test',
  fallbackScheme: 'https',
);

final callbackFromResolver = await resolveAndSanitizeRedirectWithResolver(
  payload,
  queryParameters,
  requestUri: requestUri,
  fallbackHost: 'app.test',
  fallbackScheme: 'https',
  resolveRedirect: (candidate) async => candidate,
);
```

## Callback helper for redirect fallbacks

Use `resolveAuthRedirectTargetWithFallback` when your adapter supports
redirect callbacks but should preserve a framework-provided fallback URL.

```dart
final resolvedUrl = await resolveAuthRedirectTargetWithFallback<MyContext>(
  callback: callbacks.redirect,
  context: AuthRedirectCallbackContext<MyContext>(
    context: context,
    url: '/requested',
    baseUrl: 'https://app.test',
  ),
  fallbackUrl: '/requested',
);
```

When you already have an `AuthCallbacks<TContext>` instance, use the compact
wrapper:

```dart
final resolvedFromCallbacks = await resolveAuthRedirectWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  url: '/requested',
  baseUrl: 'https://app.test',
);
```

The same pattern exists for JWT/session callback orchestration:

```dart
final signInRedirect = await resolveAuthSignInRedirectWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  user: user,
  strategy: AuthSessionStrategy.session,
  callbackUrl: '/requested',
);

// Throws AuthFlowException('sign_in_blocked') if callbacks.signIn denies.

final claims = await resolveAuthJwtClaimsWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  user: user,
  strategy: AuthSessionStrategy.jwt,
);

final sessionPayload = await resolveAuthSessionPayloadWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  session: session,
  strategy: AuthSessionStrategy.session,
);

final jwtIssue = await issueAuthJwtSessionWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  options: jwtOptions,
  user: user,
  strategy: AuthSessionStrategy.jwt,
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

// Config/manifest-driven gate registration that preserves unmanaged entries:
final managed = <String>{};
final registered = registerGateCallbacksSafely<Map<String, dynamic>>(
  gates.registry,
  <String, AuthGateCallback<Map<String, dynamic>>>{
    'posts.publish': rolesGate(<String>['editor']),
  },
  managed: managed,
);
managed
  ..clear()
  ..addAll(registered);
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

For adapters that keep issued-at metadata, use
`syncAuthSessionRefresh` to apply initialize/refresh/keep behavior:

```dart
syncAuthSessionRefresh(
  issuedAtValue: session['__auth.session.issued_at'] as String?,
  updateAge: const Duration(minutes: 5),
  writeIssuedAt: (value) {
    session['__auth.session.issued_at'] = serializeAuthSessionIssuedAt(value);
  },
  touchSession: () => sessionTouch(),
);
```

## Minimal adapter skeleton

Use a small framework-specific adapter that maps your persistence layer into
`server_auth` contracts:

```dart
class MyAuthAdapter extends AuthAdapter {
  final Map<String, AuthUser> usersById = <String, AuthUser>{};

  @override
  FutureOr<AuthUser?> getUserById(String id) {
    return usersById[id];
  }

  @override
  FutureOr<AuthUser> createUser(AuthUser user) {
    usersById[user.id] = user;
    return user;
  }

  @override
  FutureOr<AuthSession?> getSession(String sessionToken) {
    // Query your DB or cache here.
    return null;
  }
}
```

Keep adapters focused on boundary mapping and keep provider/JWT/gate logic in
`server_auth`.

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
See `example/README.md` for run instructions and expected output.

## Migration Notes

If older code imported provider factories or auth primitives from Routed
entrypoints, switch to direct `server_auth` imports to keep auth logic reusable
across frameworks.

## Validation

```bash
dart analyze
dart test
dart run example/main.dart
```

## License

MIT
