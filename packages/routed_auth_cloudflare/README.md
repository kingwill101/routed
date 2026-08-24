# routed_auth_cloudflare

Durable Cloudflare D1 persistence for `package:server_auth`. The package is a
small host adapter: `server_auth` remains framework-neutral, while this package
depends explicitly on `server_auth` and the host-neutral D1 types from
`routed_node`.

```dart
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/server_auth.dart';

Future<CloudflareD1AuthStore> authStore(CloudflareEnvironment env) {
  return CloudflareD1AuthStore.open(
    env.d1('AUTH_DB'),
    schema: const CloudflareD1AuthSchema(
      tablePrefix: 'my_app_auth',
    ),
  );
}
```

`CloudflareD1AuthStore.open` applies typed, idempotent migrations. There is no
YAML configuration and application code does not import `package:web` or use
`dart:js_interop`.

For a complete Worker entrypoint, Wrangler configuration, local SQLite-backed
smoke test, and curl walkthrough, see the runnable
[Cloudflare D1 auth example](../../examples/cloudflare_auth).

When an external authentication plugin is removed from a deployment, preserve
its namespace in the durable safety inventory until its records have a
backend-owned cleanup path:

```dart
final store = await CloudflareD1AuthStore.open(
  env.d1('AUTH_DB'),
  historicalAuthenticationMethodNamespaces: const ['legacy_device'],
);
```

If a historical namespace is absent from the active authoritative contributors,
safe authentication-method removal fails closed. This prevents a removed
plugin's credentials from being invisible during fallback checks.

For hard deletion of user-owned plugin records, configure the matching
storage namespace in `AuthOptions.historicalUserDataNamespaces`. The D1
deletion coordinator supports this capability and fails closed when a
previously deployed contributor is absent.

Anonymous authentication is selected like any other server plugin; the root D1
adapter itself supplies the required mutation capability:

```dart
final store = await authStore(env);
final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [AnonymousPlugin<MyRequestContext>()],
);
```

Creation, authenticated deletion, and upgrade finalization execute as D1
transactions. Operation IDs, user bindings, and target bindings are persisted
only as non-reversible digests. Creation receipts are scrubbed by typed or
generic hard deletion; retained delete/upgrade receipts never contain an
`AuthUser` payload. Replay retention defaults to one day and 10,000 records and
is configured with the typed `anonymousReplayTtl` and `anonymousMaxReceipts`
arguments to `CloudflareD1AuthStore.open`. Once a receipt expires or is evicted,
the operation is no longer replayable; hard-deleted user IDs remain unavailable.

API keys use the separately selected D1 sub-store; the root adapter does not
enable the plugin implicitly:

```dart
final store = await CloudflareD1AuthStore.open(
  env.d1('AUTH_DB'),
  schema: const CloudflareD1AuthSchema(tablePrefix: 'my_app_auth'),
  apiKeyMaxRecords: 20_000,
);

final apiKeys = AuthApiKeyPlugin<MyRequestContext>(
  store: store.apiKeys,
  countsAsPrimaryAuthenticationMethod: false,
  sessionExchangeEnabled: false,
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [apiKeys],
);
```

Migration v9 stores only the secret digest and safe key metadata: owner, name,
prefix, scopes, expiry, last-use, and revocation timestamps. The raw key remains
in the one-time create or rotate result and never enters D1. Issue, touch,
revoke, rotate, resolve, and list operations are bounded by
`apiKeyMaxRecords`; rotation may replace its old row at capacity but never
leaves the table above the configured bound. Coordinated hard deletion compiles
the API-key cleanup plan into the same D1 batch as core user deletion. Because
the table is owned by the root adapter, core deletion also scrubs it when a
previously installed API-key plugin is no longer composed.

When `countsAsPrimaryAuthenticationMethod` is enabled, safe revocation is
available only if the exact `store.apiKeys` instance and every fallback method
belong to the authoritative D1 topology. Mixed or foreign stores fail closed;
there is no process-local callback transaction or compatibility fallback.

Phone authentication uses the root adapter's typed backend. Add the plugin and
keep SMS delivery as an application-owned post-commit callback:

```dart
final store = await authStore(env);
final phone = PhoneNumberPlugin<MyRequestContext>(
  sendCode: (delivery) => sms.send(
    delivery.phoneNumber,
    delivery.code,
  ),
  codeHashKey: authPhoneCodeHashKey,
  allowSignUp: true,
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [phone],
);
```

Append-only migration v11 adds bounded phone challenges, verified phone
identities, and idempotency receipts. Challenge codes and issuance IDs cross
the adapter only as digests; D1 stores no deliverable SMS code or raw operation
ID. Verification updates attempts or lockout, consumes the challenge, creates
or resolves the user, binds the phone identity, and projects the verified phone
attributes in one D1 batch. Configure the global challenge bound with
`phoneNumberMaxVerifications`. Hard deletion removes phone identities,
challenges, and receipts with the user, including when the phone plugin is no
longer composed.

WebAuthn uses the root adapter's optional typed capability. Install only the
plugin and its provider; application code does not construct D1 substores:

```dart
final store = await authStore(env);
final passkeys = WebAuthnPlugin<MyRequestContext>(
  provider: WebAuthnProvider(
    getUserInfo: resolvePasskeyUser,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'example.com',
      name: 'Example',
      origin: 'https://example.com',
    ),
  ),
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [passkeys],
);
```

Append-only migration v10 adds bounded challenge and authenticator tables.
Challenges persist only a SHA-256 digest and exact ceremony bindings and are
deleted by one atomic consume. Credential IDs are globally unique, signature
counters use compare-and-set updates, and public-key, transport, name, and
identifier fields are bounded. Configure global limits with
`webAuthnChallengeMaxRecords` and `webAuthnAuthenticatorMaxRecords` when
opening the store. Raw challenges and attestation objects are never persisted.

Passkey removal rechecks same-domain password, OAuth, email, API-key, and other
passkey fallbacks in the conditional D1 mutation. Mixed or future unsupported
stores fail closed. Hard deletion removes bound challenges and passkeys in the
root batch, rolls back with the user, and still cleans the backend-owned tables
after the WebAuthn plugin is removed. A deletion receipt prevents a deleted
user ID from reactivating retained or concurrently created credentials.

Provider mode must use all three OAuth stores from the same opened adapter:

```dart
final store = await authStore(env);
final oauthProvider = OAuthProviderModePlugin<MyRequestContext>(
  clientStore: store.oauthClientStore,
  authorizationCodeExchangeStore:
      store.oauthAuthorizationCodeExchangeStore,
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [oauthProvider],
);
```

The adapter persists client-secret, authorization-code, access-token, and
refresh-token digests only. Authorization-code exchange uses one D1 atomic
batch to revalidate every binding, insert the prepared token-digest record,
and consume the code. A durable runtime rejects in-memory, foreign-database,
or otherwise split OAuth store topologies instead of falling back.

Managed SCIM is an independently selected server plugin. Its D1 store is
obtained from the same opened adapter, so connection management, bearer
resolution, replay metadata, and coordinated user deletion share one durable
transaction domain:

```dart
final store = await authStore(env);
final scimConnections = AuthScimConnectionPlugin<MyRequestContext>(
  store: store.scimConnectionStore,
  authorize: (request) async {
    final user = request.invocation.user;
    if (user == null) return null;
    final access = await loadDirectoryAccess(
      request.invocation.context,
      request.organizationId,
    );
    if (access == null) return null;
    return AuthScimConnectionManagementPrincipal(
      tenantId: access.tenantId,
      organizationId: access.organizationId,
      subjectId: user.id,
    );
  },
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [scimConnections],
);
```

Only bearer digests and safe credential metadata are stored. Connection
creation, issuance, and rotation write their replay identity in the same D1
batch, so a committed retry returns metadata without reconstructing the raw
secret. The default replay lifetime is one day and can be changed with the
typed `scimReplayTtl` argument to `CloudflareD1AuthStore.open`.

The local tests run `AuthStoreConformanceSuite`,
`AuthAnonymousStoreConformanceSuite`, `AuthApiKeyStoreConformanceSuite`, and
`verifyOAuthAuthorizationCodeExchangeStoreConformance` against a deterministic
SQLite-backed implementation of the public `CloudflareD1Database` API. They
inject mid-batch faults to prove that anonymous identities, replay receipts,
API-key rotation, OAuth code consumption, and token persistence roll back with
their transaction.

The root adapter implements `AuthUsernameStore`: normalized username
registration and rename commit the user projection and password credential in
one D1 batch, and contention relies on D1 uniqueness constraints. Safe username
removal rechecks every supported fallback inside that same store-owned batch
and fails closed for mixed or unsupported authentication-method stores.

The local tests also run `verifyAuthUsernameStoreConformance` against that
deterministic public D1 fake. The separate
[live harness](test/live/README.md) is intentionally not part of the default
test command. On 2026-08-21, a disposable live D1 run passed the core,
anonymous, managed-SCIM, phone v11, API-key v9, WebAuthn v10, username,
OAuth-exchange, rollback, and prefix-isolation cases. Fault-injection cases
remain local-only. The harness deleted its owned database, and a separate
Wrangler listing confirmed that no matching resource remained.

The adapter also implements `AuthMagicLinkBackend` and `AuthEmailOtpBackend`.
Magic-link replacement and consume-plus-user resolution, and OTP attempt/
consume-plus-user transitions, execute in guarded D1 batches. Only token
digests and keyed OTP digests cross the persistence boundary. Adapter tests run
`verifyAuthEmailBackendConformance` from `package:server_auth/testing.dart` and
inject a failure at every statement in each consume batch to prove rollback.
Email delivery and Routed session/cookie issuance remain postcommit host
boundaries and are not represented as D1 transactions.

Rate limiting remains an application concern. Use Routed's built-in adapter
with the existing `server_rate_limit` service rather than coupling this D1
auth adapter to a second persistence schema:

```dart
final backend = CacheRateLimiterBackend(
  repository: RepositoryImpl(ArrayStore(), 'rate-limit', ''),
);
final service = RateLimitService(
  compileRateLimitPolicies(
    specs: const [
      RateLimitPolicySpec(
        name: 'auth-ip',
        match: '/auth/**',
        method: null,
        strategy: RateLimitStrategy.slidingWindow,
        capacity: 30,
        interval: Duration.zero,
        window: Duration(minutes: 1),
        period: Duration.zero,
        burstMultiplier: null,
        key: RateLimitKeySpec.ip(),
      ),
    ],
    backend: backend,
    defaultFailover: RateLimitFailoverMode.block,
  ),
);

final deployment = AuthDeploymentPresets.secureSessionProduction<EngineContext>(
  rateLimiter: RoutedAuthRateLimiter(service),
  // ... store, providers, and boundary
);
```

`ArrayStore` is suitable for tests and a single process/isolate. Applications
that need a shared limit should provide a shared `Repository` to the same
built-in `CacheRateLimiterBackend`; this package does not silently turn the D1
auth store into a rate-limit store.

The independent
[deployed Worker auth harness](tool/deployed_worker/README.md) verifies Routed's
session, JWT, plugin, external-provider, and browser-shaped WebAuthn contracts
inside an already-deployed Cloudflare Worker. It is also opt-in and does not
create, update, or delete Cloudflare resources.

The full suite was run against a temporary Worker on 2026-08-21. The Worker
and its conformance secret were deleted after the run. The external-provider
browser-binding case uses a distinct framework-session cookie; the separate
auxiliary OAuth state-cookie fallback is covered by Routed's route tests.

Cloudflare D1 exposes atomic statement batches, but not a transaction that can
span the arbitrary callback required by `AuthAccountDeletionStore`. The
adapter therefore fails closed by not advertising that optional capability;
the conformance case is reported as skipped. Core records are never partially
deleted under a false transaction guarantee. The separate typed user-deletion
coordinator does compose guarded plugin and core cleanup into one D1 batch,
including OAuth authorization-code and token records. It accepts only
backend-bound typed mutation plans it can compile into that batch; supported
authentication-method removal uses those plans, while mixed external stores
fail closed instead of advertising a false transaction guarantee.
