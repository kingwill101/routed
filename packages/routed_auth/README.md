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
  routed: ^0.5.0
  server_auth: ^0.1.0
  routed_auth: ^0.2.0
  routed_rate_limit: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:server_auth/server_auth.dart';

void main() async {
  final options = AuthOptions<EngineContext>(
    store: InMemoryAuthStore(), // Replace with a durable AuthStore in production.
    storeMode: AuthStoreMode.ephemeral,
    providers: const <AuthProvider>[],
  );

  // Bind typed options before providers boot so AuthServiceProvider creates
  // the manager and registers AuthRoutes during initialization.
  final engine = Engine(
    providers: [
      ...Engine.defaultProviders,
      AuthServiceProvider(),
    ],
  );
  engine.container.instance<AuthOptions<EngineContext>>(options);
  await engine.initialize();

  engine.get(
    '/account',
    (ctx) => ctx.json({'authenticated': true}),
    middlewares: [requireAuthenticated()],
  );

  await engine.serve(port: 8080);
}
```

For production, use a durable `AuthStore` and set
`AuthServiceProvider(requireDurableStore: true)` so startup rejects an
accidental in-memory store.

For a slim composition, import `routed_auth` directly and add
`AuthServiceProvider()` after `Engine.defaultProviders`. Add typed provider
instances to `AuthOptions.providers`; no auth provider registry or
configuration manifest is required. Server plugins can be composed directly
on the same options object:

```dart
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:server_auth/server_auth.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

final authRateLimitService = RateLimitService(const []);
final options = AuthOptions<EngineContext>(
  providers: const <AuthProvider>[],
  store: InMemoryAuthStore(),
  storeMode: AuthStoreMode.ephemeral,
  browserProtection: const AuthBrowserProtectionOptions(
    allowedOrigins: ['https://app.example.com'],
  ),
  rateLimiter: RoutedAuthRateLimiter(authRateLimitService),
);

final engine = Engine(
  providers: [
    ...Engine.defaultProviders,
    AuthServiceProvider(),
    RoutedRateLimitProvider(
      RateLimitConfig(service: authRateLimitService),
    ),
  ],
);
engine.container.instance<AuthOptions<EngineContext>>(options);
await engine.initialize();
```

`AuthServiceProvider` creates the `AuthRuntime` and exposes it through the
`AuthManager`. Applications provide a typed `AuthStore`; persistence is not
created implicitly by the framework. `RoutedAuthRateLimiter` is exported by
`routed_rate_limit` and adapts its existing method/path/IP policies to auth
operations. Configure `EngineConfig.trustedProxies` (or the typed routed
security provider) before relying on forwarded client-IP headers.

OAuth state, PKCE verifiers, OIDC nonces, and callback URLs are stored in the
typed `AuthStore.oauthChallenges` boundary and consumed atomically during the
callback. A durable store must implement that operation transactionally and
protect the short-lived challenge values at rest. Routed also binds each OAuth
challenge to a short-lived, HTTP-only browser state cookie, so a callback
started in another browser is rejected before the durable challenge is
consumed. The cookie uses `SameSite=None` over HTTPS to support provider
`form_post` callbacks and `SameSite=Lax` during local HTTP development.

Email magic-link verification is bound to a separate short-lived, HTTP-only
browser cookie as well. This prevents a user from being silently signed into
another person’s account by opening that person’s magic link. Applications
that intentionally support cross-device magic-link completion should expose an
explicit confirmation step rather than disabling this binding implicitly.

Password-reset tokens use the separate `AuthStore.passwordResetTokens`
boundary. Store implementations must hash them and consume them atomically;
`server_auth` also provides framework-agnostic helpers for issuing tokens,
replacing password credentials, rotating per-user JWT versions, and revoking
server sessions. HTTP delivery is supplied through
`AuthOptions.passwordResetSender`. When that sender is configured, Routed
registers:

- `POST /auth/password-reset/request`
- `POST /auth/password-reset/confirm`

Authenticated sessions can change their password through
`POST /auth/password/change`. The request requires the current password and
the new password; a successful change revokes all server sessions or rotates
the JWT version and expires the current auth cookie.

The request route always returns the same accepted response for known and
unknown emails. JWTs without the current per-user version are rejected.

Server-side session management is available through:

- `GET /auth/sessions`
- `POST /auth/sessions/revoke`
- `POST /auth/sessions/revoke-others`

Session responses include safe device metadata and never include the persisted
session-token digest. These routes are not registered for JWT sessions.

When `TwoFactorPlugin` is composed, Routed also registers:

- `GET /auth/2fa/status`
- `POST /auth/2fa/enroll`
- `POST /auth/2fa/enroll/verify`
- `POST /auth/2fa/verify`
- `POST /auth/2fa/recovery-code`
- `POST /auth/2fa/recovery-codes/regenerate`
- `POST /auth/2fa/disable`
- `POST /auth/2fa/challenge/verify`
- `POST /auth/2fa/challenge/recovery-code`
- `POST /auth/2fa/trusted-devices/revoke`
- `POST /auth/2fa/step-up`
- `POST /auth/2fa/step-up/revoke`

The account-management routes require an authenticated session and all
state-changing routes use the existing browser and CSRF protections.
Credential sign-ins for enabled users return a `202 two_factor_required`
response until the challenge route verifies TOTP.
The challenge request may include `trustDevice: true`; after successful TOTP,
Routed sets an expiring HTTP-only trusted-device cookie. The revoke route
invalidates all trusted devices for the current user. Pending recovery-code
completion is available when the plugin is configured with an atomic pending
recovery store.
When `stepUpStore` is configured, `POST /auth/2fa/step-up` verifies a fresh
TOTP code and sets a short-lived, session-bound HTTP-only proof cookie. Routed
consumers can enforce it with `AuthManager.requireTwoFactorStepUp` before
sensitive actions; `POST /auth/2fa/step-up/revoke` clears the proof.

## API-key authentication

Compose `AuthApiKeyPlugin` in `AuthOptions.plugins` to add:

- `GET /auth/api-keys/list`
- `POST /auth/api-keys/create`
- `POST /auth/api-keys/rotate`
- `POST /auth/api-keys/revoke`
- `POST /auth/api-keys/exchange` when session exchange is explicitly enabled

The raw secret is returned only by create and rotate. To authenticate service
requests, add the middleware after the plugin is composed:

```dart
final apiKeys = AuthApiKeyPlugin<EngineContext>(store: myApiKeyStore);
final apiKeyMiddleware = apiKeyAuthentication(
  plugin: apiKeys,
  userStore: myAuthStore.users,
);
```

It accepts `X-API-Key` and `Authorization: ApiKey ...`. A verified key becomes
the request principal without creating a browser session. If
`sessionExchangeEnabled: true` is configured, the same header can be posted to
`/auth/api-keys/exchange` to create a normal server session. Use
`currentApiKey` to inspect scopes in application middleware or handlers.

## Organizations

Compose `OrganizationPlugin<EngineContext>` to opt in. `AuthRoutes` discovers
its portable descriptors and automatically mounts the organization API; there
is no separate route-registration call. If the plugin is absent, every
organization route is absent.

The API lives under `/auth/organization/` and covers create/check/list/get/
update/delete/set-active; member list/remove/role/leave; invitation invite/
accept/reject/cancel/get/list; permission checks and dynamic-role CRUD; and
team/team-member CRUD plus active-team selection. Read operations use `GET`;
mutations use `POST` and inherit Routed's authentication, origin, Fetch
Metadata, CSRF, rate-limit, generic-error, and retry-header handling from the
operation descriptor.

Server-session deployments may persist active organization/team convenience
state. Membership is still revalidated on every scoped request, and stale
selection is cleared. JWT clients keep selection locally and send explicit
organization/team IDs; setting active context never reissues a JWT.

Use `Haigate.organizationContext`, `Haigate.canInOrganization`, and
`Haigate.ownsOrCanInOrganization` for explicit tenant membership, permission,
and resource-owner checks. These helpers do not merge organization roles into
the user's global principal.

## Administration

Compose `AdminPlugin<EngineContext>` to opt in. `AuthRoutes` automatically
mounts its portable descriptors under `/auth/admin/`; without the plugin,
those routes do not exist. The API covers user create/list/get/update/delete,
role/password changes, bans, permission checks, target-session administration,
and guarded server-session impersonation.

All operations require an authenticated session. Mutations use `POST` and
inherit Routed's origin, Fetch Metadata, CSRF, namespaced rate-limit, generic
error, and retry-header handling. User reads and session reads return safe
projections: password hashes, raw session tokens, token hashes, provider
tokens, and internal hook errors are never serialized.

Routed consults plugin authentication policies before a two-factor challenge,
before issuing a session, and whenever a session is resolved. Consequently an
active Admin ban blocks credentials, email, OAuth, two-factor completion,
server-session reuse, and Routed-issued JWT reuse. Sensitive mutations revoke
server sessions and rotate JWT versions.

Impersonation is intentionally unavailable with JWT sessions. With server
sessions it rotates the current session, records the original administrator in
server-side metadata, defaults to one hour, prevents chaining, and restores a
fresh administrator session when stopped. The impersonated identity receives
only the target user's roles and permissions.

See the documentation site's Administrative Auth guide for setup, custom
permissions, adapter requirements, typed-client usage, and the complete route
catalogue.
