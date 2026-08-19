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

Use the package umbrella library for the public API.

## Package Selection

- Use `server_auth` for auth runtime primitives and provider implementations.
- Use `server_contracts` for contract-only abstractions.
- Use adapter packages (`routed`, `shelf_auth`, etc.) for framework-specific HTTP/session wiring.

## Quick start

```dart
import 'package:server_auth/server_auth.dart';

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

## Typed Dart client

`AuthClient` keeps consumers from duplicating auth route names, JSON parsing,
CSRF presentation, and session-cookie handling:

```dart
final auth = AuthClient(
  baseUrl: Uri.parse('https://example.com'),
  cookieStore: myPersistentCookieStore, // Optional for mobile persistence.
);

final session = await auth.signInWithCredentials(
  email: 'ada@example.com',
  password: password,
);
print(session.user.id);
```

The default `InMemoryAuthClientCookieStore` is suitable for tests and
short-lived clients. Browser, mobile, and desktop applications can implement
`AuthClientCookieStore` with their platform's secure persistence. Use
`setBearerToken` when the server is configured for bearer/JWT sessions.

The client follows the framework adapter's public auth contract: providers,
CSRF, sessions, credentials, email verification, OAuth redirects, and
sign-out. It does not persist secrets or silently provision local accounts.

## Optional two-factor feature

Compose `TwoFactorFeature` when an application needs TOTP and recovery codes:

```dart
final twoFactor = TwoFactorFeature<void>(
  store: myTwoFactorStore,
  challengeStore: myTwoFactorChallengeStore,
  pendingRecoveryStore: myPendingRecoveryStore,
  trustedDeviceStore: myTrustedDeviceStore,
  stepUpStore: myStepUpStore,
  secretProtector: mySecretProtector,
);
```

The feature owns enrollment verification, TOTP validation, lockout state,
recovery-code hashing and atomic consumption, regeneration, disablement, and
expiring trusted-device tokens. Explicit trusted-device issuance requires a
fresh TOTP code. Trusted-device records store only token
digests; the Routed adapter places the raw token in an HTTP-only cookie and
supports revoking all devices. Credential sign-ins for enabled users return a
short-lived pending challenge and issue a session only after TOTP completion.
The pending challenge can optionally issue a trusted-device cookie after
successful TOTP verification. Configure `pendingRecoveryStore` with a
durable implementation when recovery codes must complete pending sign-ins; it
must consume the recovery digest and challenge in one transaction.
Configure `stepUpStore` to issue short-lived proofs bound to the current
authenticated session before sensitive actions. The adapter should call its
step-up requirement helper at those action boundaries.
`AuthTwoFactorSecretProtector` is required
so durable applications can use their own key-management system; the
plaintext protector is intended only for tests and ephemeral examples.

## Optional organization feature

Organizations are opt-in. Nothing is registered unless an
`OrganizationFeature` is included in `AuthOptions.features`:

```dart
final organizations = OrganizationFeature<MyRequestContext>(
  store: myOrganizationStore,
  options: const AuthOrganizationOptions(
    teams: AuthOrganizationTeamsOptions(enabled: true),
    dynamicRoles: true,
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: providers,
  store: myAuthStore,
  features: [organizations],
);
```

The feature owns organizations, memberships, email-bound invitations,
organization-scoped permissions, dynamic roles, teams, typed lifecycle hooks,
redacted audit events, and post-commit warnings. Organization roles remain
separate from global `AuthPrincipal.roles`.

`AuthOrganizationStore` is a logical, atomic persistence contract. It contains
no SQL, D1 bindings, table names, migrations, or query builders. Production
adapters must implement its create/accept/capacity/last-owner/role-rename and
cascade operations transactionally. `InMemoryAuthOrganizationStore` is only
for tests and local development. The feature also advertises logical entity,
relationship, uniqueness, index, and atomic-operation descriptors so adapters
can build physical schemas without coupling `server_auth` to a database.

Teams and dynamic roles are separately disabled by default. Default limits
match the Better Auth benchmark: 100 members, 100 pending invitations, and a
48-hour invitation lifetime. A built-in opaque ID generator is used unless an
application supplies one. Custom non-opaque invitation IDs require a verified
session email before they can be acted upon.

Core and feature clients share `AuthClientTransport` for cookies, bearer
tokens, CSRF refresh, timeouts, redirects, and bounded error parsing:

```dart
final transport = AuthClientTransport(
  baseUrl: Uri.parse('https://example.com'),
  cookieStore: myCookieStore,
);
final auth = AuthClient(
  baseUrl: Uri.parse('https://example.com'),
  transport: transport,
);
final organization = AuthOrganizationClient(transport: transport);
```

`AuthOrganizationClient` keeps active organization/team selection locally and
sends the selected IDs explicitly. This works with JWTs without silently
reissuing tokens; Routed server sessions may additionally persist the same
selection as a convenience.

## Optional API-key feature

Compose `AuthApiKeyFeature` for service-client credentials:

```dart
final apiKeys = AuthApiKeyFeature<MyRequestContext>(
  store: myApiKeyStore,
  sessionExchangeEnabled: true, // Only when API keys may create sessions.
);

final options = AuthOptions<MyRequestContext>(
  store: myAuthStore,
  providers: providers,
  features: [apiKeys],
);
```

Only a digest is persisted. The raw key is returned once when it is created or
rotated; listing returns metadata, scopes, expiry, last-use, and revocation
state. Production applications should provide a durable `AuthApiKeyStore` and
implement its atomic touch, revoke, and rotate operations transactionally.
Routed can additionally expose `POST /auth/api-keys/exchange` when
`sessionExchangeEnabled` is true. It accepts the API key from an auth header
and creates a normal server-side session; it is disabled by default.

## Auth runtime and typed stores

Integrations compose an `AuthRuntime` from typed domain stores and feature
modules. `AuthStore` is the required persistence boundary; there is no legacy
adapter bridge or implicit fallback:

```dart
final options = AuthOptions<void>(
  providers: [google],
  store: InMemoryAuthStore(), // Use a database-backed AuthStore in production.
  storeMode: AuthStoreMode.ephemeral,
  features: [MyAuthFeature()],
);

final runtime = AuthRuntime<void>(options: options);
final user = await runtime.store.users.findByEmail('user@example.com');
```

`InMemoryAuthStore` stores explicit password-credential records but is volatile
and intended only for tests and local development. The built-in credentials
flow uses `AuthOptions.passwordHasher` (Argon2id by default) and
`AuthOptions.passwordPolicy` (12–1,024 characters by default). Durable stores
must persist only encoded password hashes and apply their own database
transaction policy around registration and login. Providers that supply custom
`authorize` or `register` callbacks own validation for those callback inputs.

`AuthOptions` defaults to durable storage and rejects an unannotated
`InMemoryAuthStore`. If ephemeral storage is intentional for a test or local
demo, set `storeMode: AuthStoreMode.ephemeral`. Production adapters should
enable their durable-store boot validation.

Authentication rate limits are configured as a typed policy on
`AuthOptions.rateLimiter`. The policy receives the operation, provider ID,
framework context, and optional login identifier; it never receives a
password, OAuth code, bearer token, or verification token. Routed invokes the
policy before its built-in auth operations and custom callback providers:

```dart
final options = AuthOptions<MyRequestContext>(
  providers: providers,
  store: myStore,
  rateLimiter: MyAuthRateLimiter(),
);
```

Return `AuthRateLimitDecision.block(retryAfter: ...)` to produce a stable
`rate_limited` failure in an adapter. The adapter owns the client identity
used for the limit, including any trusted-proxy policy.

Features receive the shared `AuthStore` during configuration. They own one
auth concern at a time and may contribute portable endpoint, logical schema,
typed-client, and namespaced rate-limit descriptors. The registry rejects
duplicate feature IDs and endpoint method/path pairs, then freezes the feature
topology after runtime boot.

For Routed applications, use `routed_auth`: initialize `AuthServiceProvider`
alongside `Engine.defaultProviders`, then add the adapter's auth middleware and
routes. `server_auth` itself never registers framework providers.

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

final verifiedSession = await verifyAuthJwtSessionToken(
  token: issued.token,
  options: options,
);
print(verifiedSession?.user.id);

final resolvedSession = await resolveAuthJwtSessionWithRefresh(
  token: issued.token,
  options: options,
  updateAge: const Duration(minutes: 15),
  resolveClaims: (claims, user) => claims,
);
print(resolvedSession?.refreshCookie != null); // refreshed or not
```

## Bearer validation helpers for adapters

Use `verifyJwtBearerAuthorizationAndWriteAttributes` in framework middleware to
share JWT bearer auth orchestration (token extraction, verification, request
attribute writes, and optional callback):

```dart
final result = await verifyJwtBearerAuthorizationAndWriteAttributes<MyContext>(
  authorizationHeader: request.header('authorization'),
  verifier: jwtVerifier,
  setAttribute: request.setAttribute,
  context: context,
  onVerified: (payload, ctx) async {
    if (payload.claims['scope'] == null) {
      throw JwtAuthException('missing_scope');
    }
  },
);

print(result.payload.subject);
```

For OAuth introspection middleware, use
`validateOAuthBearerAuthorizationAndWriteAttributes`:

```dart
final validation =
    await validateOAuthBearerAuthorizationAndWriteAttributes<MyContext>(
      authorizationHeader: request.header('authorization'),
      introspector: oauthIntrospector,
      setAttribute: request.setAttribute,
      context: context,
      onValidated: (result, ctx) async {
        if (result.scope?.contains('api:read') != true) {
          throw OAuth2Exception('insufficient_scope');
        }
      },
    );

print(validation.result.raw);
```

## Email verification orchestration helpers

Use `startAuthEmailSignIn` to share the email verification start flow:

```dart
final payload = await startAuthEmailSignIn<MyContext>(
  store: store,
  provider: emailProvider,
  context: context,
  email: 'user@example.com',
  callbackUrl: '/dashboard',
  sessionStrategy: AuthSessionStrategy.session,
  callbackKey: '_auth.callback',
  writeSession: (key, value) => sessionStore[key] = value,
);

print(payload.pendingResult.session.strategy);
```

Use `resolveAuthEmailVerificationSignIn` in callback handlers:

```dart
final resolved = await resolveAuthEmailVerificationSignIn(
  store: store,
  email: email,
  token: token,
  callbackKey: '_auth.callback',
  readSession: (key) => sessionStore[key],
);
```

## Credentials orchestration helpers

Use `requireAuthorizedCredentialsSignIn` and
`requireAuthorizedCredentialsRegistration` to perform provider/adapter
credential resolution with standard auth errors:

```dart
final user = await requireAuthorizedCredentialsSignIn(
  store: store,
  provider: credentialsProvider,
  context: context,
  credentials: credentials,
);
```

## OAuth callback orchestration helper

Use `resolveOAuthSignInForProvider` in framework adapters to share OAuth
callback exchange/profile/user resolution logic without depending on Routed.

```dart
final resolved = await resolveOAuthSignInForProvider<MyContext, Map<String, dynamic>>(
  store: store,
  context: context,
  provider: oauthProvider,
  code: authorizationCode,
  codeVerifier: pkceVerifier,
  httpClient: httpClient,
);

print(resolved.user.id);
print(resolved.profile);
```

`resolveOAuthSignInForProvider` links the account through the atomic store
boundary before returning. A conflicting canonical owner fails with
`account_link_conflict`.

OAuth email linking requires an explicit `verified` or `email_verified` claim
from the provider. Unverified email values are not persisted as the local
user's email and cannot be used as the external account identifier; providers
must supply a stable profile subject or the adapter's fallback account ID.

For framework adapters, prefer the typed OAuth challenge store on `AuthStore`.
Its `consume` operation must atomically delete and return a matching challenge;
this prevents concurrent callback replay across processes. Routed uses this path
by default. Durable stores must protect the PKCE verifier, nonce, and callback
URL as short-lived secrets.

```dart
final start = await resolveOAuthAuthorizationStart<MyContext, Map<String, dynamic>>(
  context: context,
  provider: oauthProvider,
  stateKey: '_auth.state',
  pkceKey: '_auth.pkce',
  callbackKey: '_auth.callback',
  challengeStore: store.oauthChallenges,
  callbackUrl: '/dashboard',
  writeSession: (key, value) => sessionStore[key] = value,
);
```

The session-backed form remains available for adapters that have not adopted
the typed challenge contract:

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

For callback handlers, `resolveOAuthCallbackSessionValues` reads state/verifier/
callback URL using the same key contract:

```dart
final values = resolveOAuthCallbackSessionValues(
  providerId: oauthProvider.id,
  stateKey: '_auth.state',
  pkceKey: '_auth.pkce',
  callbackKey: '_auth.callback',
  readSession: (key) => sessionStore[key],
);
```

Or use the higher-level callback helper to validate state, resolve sign-in,
and persist linked accounts in one call:

```dart
final callback = await resolveOAuthCallbackSignInForProvider<MyContext, Map<String, dynamic>>(
  store: store,
  context: context,
  provider: oauthProvider,
  code: authorizationCode,
  receivedState: stateFromRequest,
  stateKey: '_auth.state',
  pkceKey: '_auth.pkce',
  callbackKey: '_auth.callback',
  readSession: (key) => sessionStore[key],
  httpClient: httpClient,
);

print(callback.signIn.user.id);
print(callback.callbackUrl);
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

Redirect helpers return only rooted-relative or same-origin URLs. They reject
cross-origin, executable-scheme, protocol-relative, and user-info URLs; keep
the final sanitization step in framework adapters before writing `Location`.

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

final finalRedirect = await resolveAuthSignInRedirectTarget<MyContext>(
  callbacks: callbacks,
  context: context,
  user: user,
  strategy: AuthSessionStrategy.session,
  callbackUrl: '/requested',
  resolveRedirect: (candidate) => adapterResolveRedirect(candidate),
);

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

final signInResult = await resolveAuthSignInResultForStrategyWithCallbacks<MyContext>(
  callbacks: callbacks,
  context: context,
  strategy: AuthSessionStrategy.jwt,
  user: user,
  redirectUrl: finalRedirect,
  jwtOptions: jwtOptions,
);

final authResult = signInResult.result;
final issuedJwtCookie = signInResult.issuedJwt?.cookie;
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

// Managed gate registration that preserves unmanaged entries:
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

## Minimal store composition

Implement the eight typed store domains against your persistence layer. The
aggregate store only composes those domains:

```dart
class MyAuthStore implements AuthStore {
  MyAuthStore({
    required this.users,
    required this.credentials,
    required this.accounts,
    required this.sessions,
    required this.oauthChallenges,
    required this.passwordResetTokens,
    required this.jwtVersions,
    required this.verificationTokens,
  });

  @override
  final AuthUserStore users;
  @override
  final AuthCredentialStore credentials;
  @override
  final AuthAccountStore accounts;
  @override
  final AuthSessionStore sessions;
  @override
  final AuthOAuthChallengeStore oauthChallenges;
  @override
  final AuthPasswordResetTokenStore passwordResetTokens;
  @override
  final AuthJwtVersionStore jwtVersions;
  @override
  final AuthVerificationTokenStore verificationTokens;
}

final store = MyAuthStore(
  users: myUserStore,
  credentials: myCredentialStore,
  accounts: myAccountStore,
  sessions: mySessionStore,
  oauthChallenges: myOAuthChallengeStore,
  passwordResetTokens: myPasswordResetTokenStore,
  jwtVersions: myJwtVersionStore,
  verificationTokens: myVerificationTokenStore,
);
```

`AuthOAuthChallengeStore.consume` must atomically remove and return the
matching, unexpired challenge. Protect its PKCE verifier, nonce, and callback
URL fields as short-lived secrets in durable storage.

`AuthAccountStore.link` must also be atomic and create-if-absent for each
`(providerId, providerAccountId)` pair. It returns the canonical linked account
and must never replace an existing link owned by another user.

`AuthUserStore.createOrFindByEmail` must atomically enforce uniqueness for a
normalized email and report whether the returned user was created. Use this
operation for verified OAuth email linking and email sign-in callbacks.

`AuthPasswordResetTokenStore` must hash raw reset tokens, invalidate older
tokens for the same user, and consume tokens atomically. The store boundary is
available now. The framework-agnostic
`issueAuthPasswordResetTokenForUser` and `resetAuthPasswordWithToken` helpers
also cover token issuance, password replacement, JWT-version rotation, and
server-session revocation.
Adapters can use `AuthPasswordResetSender` to deliver the raw token without
persisting it. `AuthJwtVersionStore` must atomically increment a per-user
version so old JWTs fail validation after password reset or password change.

Keep persistence focused on the store contracts and keep provider/JWT/gate
logic in `server_auth`.

`AuthSessionStore` persists `AuthSessionRecord` values, not public session
payloads. The `tokenHash` field must be derived from the client-held opaque
token with `hashOpaqueToken`; implementations should use `touch`, `revoke`,
and `rotate` atomically and never store the raw token.

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
