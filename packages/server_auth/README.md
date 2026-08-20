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
  server_auth: ^0.2.0
```

## Entry points

- `package:server_auth/server_auth.dart` (umbrella export)

Use the package umbrella library for the public API.

## Package Selection

- Use `server_auth` for auth runtime primitives and provider implementations.
- Use `server_contracts` for contract-only abstractions.
- Use adapter packages (`routed`, `shelf_auth`, etc.) for framework-specific HTTP/session wiring.

## Durable store conformance

Production `AuthStore` adapters should run the framework-neutral contract from
`package:server_auth/testing.dart` against a fresh database or namespace for
every case:

```dart
final suite = AuthStoreConformanceSuite.fromStoreFactory(
  createStore: openIsolatedStore,
  disposeStore: (store) => (store as MyAuthStore).close(),
);

for (final conformanceCase in suite.cases) {
  test(conformanceCase.id, () async {
    final result = await conformanceCase.run();
    if (result.isSkipped) markTestSkipped(result.skippedReason!);
  });
}
```

The public case IDs cover canonical identity and credential races, globally
unique account links, exactly-one-winner session rotation with no persisted
losers, verification/password-reset/OAuth replay, monotonic JWT rotation,
device authorization, email OTPs, and account-deletion rollback. The suite has
no dependency on `package:test`; adapters may register its cases with any test
runner. Optional capabilities are reported as explicit skips, while every core
`AuthStore` contract is required.

## Plugin conformance

Plugin authors can validate a composed runtime with the framework-neutral
suite exported by `package:server_auth/testing.dart`:

```dart
final suite = AuthPluginConformanceSuite.fromRuntime(
  runtime,
  publicEndpointClientExceptions: {
    'mcpAuth.protectedResourceMetadata':
        'Protocol metadata is consumed by generic HTTP clients.',
  },
);

for (final conformanceCase in suite.filtered(
  include: {
    'endpoints.typed-contracts',
    'endpoints.mutation-protection',
    'endpoints.operation-semantics',
  },
)) {
  test(conformanceCase.id, conformanceCase.run);
}
```

The cases check stable composition and route identifiers, typed operation
contracts, rate-limit references, bidirectional public client-operation
mapping, safe origin/CSRF metadata, and explicit persistence/replay semantics
for every portable or host-owned mutation. Every non-server-only endpoint needs a
matching client operation unless the suite is given a non-empty explanation
for a deliberate protocol/discovery omission. Rate-limited anonymous
verification may omit session CSRF with either browser-origin validation or an
explicit non-browser policy. The reusable suite itself has no dependency on
`package:test`.

Endpoint authors must choose read-only or mutation semantics directly on the
descriptor. Mutations identify their durable, session, bounded-ephemeral, or
external persistence boundary and whether replay is idempotent, single-use,
intentionally repeatable, or currently unguarded. Atomic durable claims must
reference an operation declared by the composed plugin's public persistence
schema:

```dart
import 'package:server_auth/server_auth.dart';

final rotateEndpoint = TypedAuthEndpointDescriptor<
  Object,
  Map<String, dynamic>,
  Object?
>(
  id: 'keys.rotate',
  method: AuthOperationMethod.post,
  path: '/keys/rotate',
  semantics: const AuthOperationSemantics.mutation(
    persistence: AuthMutationPersistence.durable(
      atomicity: AuthMutationAtomicity.atomic,
      reference: AuthPersistenceOperationReference(
        schemaId: 'keys',
        atomicOperationId: 'keys.rotate',
      ),
    ),
    replaySafety: AuthMutationReplaySafety.singleUse,
  ),
  requestCodec: requestCodec,
  responseCodec: responseCodec,
  handler: rotateKey,
);
```

Conformance resolves both reference IDs against the frozen plugin topology. A
multi-step handler must use `nonAtomic` unless its adapter exposes one real
transactional operation covering the entire advertised mutation.

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

final deployment = AuthDeploymentPresets.localDevelopment<MyRequestContext>(
  providers: <AuthProvider>[google],
  trustedOrigins: [Uri.parse('http://localhost:3000')],
);
```

Bind `deployment.options` to the framework adapter, pass
`deployment.configuration` to its auth provider, and apply
`deployment.proxyPolicy` at the HTTP boundary. Production applications should
instead choose `secureSessionProduction`, `jwtApiProduction`, or
`serviceApiKeyProduction`; those presets require the durable store, trusted
origin/proxy decision, rate limiter, verified-email policy, and lifecycle
delivery choices explicitly. Providers and plugins remain opt-in inputs to
every preset.

Low-level `AuthOptions` usage carries the same typed runtime posture. Durable
options are production options: they require an exact HTTPS origin set, an
explicit direct or trusted-proxy decision, secure browser and cookie policy,
an explicit rate limiter, and an algorithm-sized secret when JWT sessions are
enabled. Ephemeral local development is an explicit opt-out:

```dart
final productionBoundary = AuthProductionBoundary(
  trustedOrigins: [Uri.parse('https://app.example.com')],
  proxyPolicy: const AuthProxyPolicy.direct(),
);

final localOptions = AuthOptions<MyRequestContext>(
  providers: [CredentialsProvider()],
  store: InMemoryAuthStore(),
  storeMode: AuthStoreMode.ephemeral,
);
```

`AuthRuntime` revalidates production posture automatically. Framework adapters
must apply `AuthProductionBoundary.proxyPolicy` at their HTTP boundary; Routed
does this through `AuthDeployment.engineConfig()`.

## Typed Dart client

`AuthClient` owns the shared transport and installs only the optional client
plugins selected by the application:

```dart
final magicLinkPlugin = AuthMagicLinkClientPlugin();
final organizationPlugin = AuthOrganizationClientPlugin();
final auth = AuthClient(
  baseUrl: Uri.parse('https://example.com'),
  cookieStore: myPersistentCookieStore, // Optional for mobile persistence.
  plugins: [magicLinkPlugin, organizationPlugin],
);

final magicLink = auth.plugins.use(magicLinkPlugin);
await magicLink.send(
  email: 'ada@example.com',
  callbackUrl: 'https://example.com/welcome',
);
final organizations = auth.plugins.use(organizationPlugin);
final values = await organizations.list();
```

The default `InMemoryAuthClientCookieStore` is suitable for tests and
short-lived clients. Browser, mobile, and desktop applications can implement
`AuthClientCookieStore` with their platform's secure persistence. Use
`setBearerToken` when the server is configured for bearer/JWT sessions.

Each optional client plugin returns one typed API and is inactive until
selected. Built-in plugins cover providers, credentials, sessions, OAuth,
magic links, email OTP, anonymous accounts, device authorization, API keys,
WebAuthn, two-factor auth, accounts, passwords, organizations, and admin
operations. The client does not persist secrets or silently provision local
accounts.

The public [auth endpoint security contract](https://kingwill101.github.io/routed/docs/routed/security/auth-endpoint-contract)
maps the core and opt-in HTTP operations to authentication, browser Origin,
CSRF, rate-limit keys, redirects, session/JWT projection, and generic public
errors. `server_auth` defines the portable descriptors; a framework adapter is
responsible for enforcing that contract.

## Optional SCIM 2.0 provisioning plugin

SCIM is a server-to-server protocol, so selecting the server plugin does not
add anything to `AuthClient`. The application owns both bearer-token
verification and durable provisioning storage:

```dart
import 'package:server_auth/server_auth.dart';

final scim = ScimPlugin<MyRequestContext>(
  tokenResolver: MyScimTokenResolver(connectionStore),
  store: MyScimProvisioningStore(database),
  options: AuthScimOptions(
    defaultPageSize: 50,
    maximumPageSize: 200,
    maximumPatchOperations: 16,
    maximumGroupMembers: 500,
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: const [],
  store: authStore,
  storeMode: AuthStoreMode.durable,
  plugins: [scim],
);
```

The resolver must digest the presented token immediately and atomically return
one immutable `AuthScimConnectionIdentity`: connection ID, credential ID,
tenant ID, organization ID, provisioning-domain ID, subject, expiry, and exact
User or Group read/write scopes. It must reject revoked or expired credentials
and must never persist, log, or return a raw token. This plugin does not issue
tokens; if an application adds issuance later, the raw value may be displayed
only once.

Each provisioning-store call receives the resolved connection context and must
enforce the exact connection, tenant, organization, and provisioning domain in
persistence. Create, replace, patch, uniqueness checks, and tombstoning each
require a real atomic store mutation. Do not advertise an adapter as SCIM-safe
when its backend cannot provide those semantics; in particular, this package
does not claim interactive multi-step transaction support for Cloudflare D1.

SCIM Users and Groups are directory resources, not authentication users,
application roles, or organization memberships. The plugin never
creates a sign-in method, grants application access, or links an existing auth
user by email. Directory lifecycle is explicit (`active`, `inactive`, or
`tombstoned`). Applications that need a stable link can implement
`AuthScimApplicationIdentityResolver`, whose lookup intentionally exposes only
the connection-bound resource ID and optional immutable `externalId`. Profile
projection, access changes, or session revocation belong in an application-owned
`AuthScimLifecycleCapability`, composed by the provisioning store within the
same backend transaction when rollback is required.

Groups contain only bounded direct references to stable SCIM User or Group
resource IDs. The provisioning store atomically owns group create, replace,
patch, direct membership mutation, and tombstoning. It must validate every
reference against the same connection, tenant, organization, and provisioning
domain, reject duplicate or conflicting members, and remove live memberships
when tombstoning. No role or access grant is inferred from a display name,
email, or Group membership.

Applications may implement `AuthScimRoleMembershipProjectionCapability` to
translate stable directory Group/member resource IDs into their own roles or
memberships. The provisioning store invokes that capability inside the same
real backend transaction when rollback across directory state and application
projection is required. Routed cannot make unrelated stores or external
systems atomic.

The selected framework adapter mounts Bearer-authenticated
`ServiceProviderConfig`, `ResourceTypes`, `Schemas`, and bounded User and Group
list/get/create/replace/patch/delete operations under its auth base path (for
Routed, `/auth/scim/v2`). Group endpoints require exact Group scopes and all
responses use `application/scim+json`. Public failures use generic SCIM error
documents and never include bearer tokens or persistence exception details.
Managed connection/credential APIs and application projection orchestration
remain explicitly deferred; there is no SCIM client plugin because directories
consume the protocol directly.

## Device authorization issuance

Device authorization uses a bounded, digest-only issuance lease. The
application token service must implement the typed idempotent issuer and use
the stable authorization ID as its durable idempotency key:

```dart
final class ApplicationDeviceTokenIssuer
    implements AuthDeviceAuthorizationTokenIssuer<MyRequestContext> {
  ApplicationDeviceTokenIssuer(this.tokens);

  final ApplicationTokenService tokens;

  @override
  Future<AuthDeviceAccessToken> issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<MyRequestContext> request,
  ) {
    return tokens.issueIdempotently(
      idempotencyKey: request.authorizationId,
      userId: request.user.id,
      clientId: request.clientId,
      scopes: request.scopes,
    );
  }
}

final deviceAuthorization = DeviceAuthorizationPlugin<MyRequestContext>(
  verificationUri: 'https://example.com/device',
  validateClient: validateDeviceClient,
  tokenIssuer: ApplicationDeviceTokenIssuer(applicationTokens),
);
```

The token service must reject reuse of an authorization ID with a different
user, client, or scope binding and return the same logical grant after an
ambiguous failure. Routed stores no raw device code, user code, lease value,
access token, or refresh token. An issuer failure releases only its matching
lease; a process crash is recoverable after lease expiry.

There is one deliberate at-most-once delivery boundary: after the application
issuer succeeds and Routed commits the authorization as consumed, loss of the
HTTP response cannot be replayed from Routed because Routed does not retain
token material. Applications requiring retryable delivery must implement that
delivery/result reference in their own token service. Routed guarantees that
retry before completion uses the same authorization ID; it does not claim
exactly-once token delivery.

## Optional SAML SSO plugin

SAML is opt-in on both sides. The application owns the immutable connection
catalog, durable replay transaction, XMLDSig implementation, and the mapping
from a signed external account key to an application user:

```dart
final saml = AuthSamlPlugin<MyRequestContext>(
  connections: mySamlConnectionCatalog,
  replayStore: myDurableSamlReplayStore,
  assertionVerifier: myXmlSignatureVerifier,
  identityResolver: mySamlIdentityResolver,
  browserBindingResolver: (context) => context.browserSessionId,
  options: AuthSamlOptions(
    redirectPolicy: AuthSamlRedirectPolicy(
      trustedOrigins: {Uri.parse('https://app.example.com')},
    ),
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: const [],
  store: authStore,
  storeMode: AuthStoreMode.durable,
  productionBoundary: productionBoundary,
  plugins: [saml],
);
```

Each `AuthSamlConnection` pins the provider ID, IdP entity ID and signing
certificate, SP entity ID, HTTPS SSO and ACS endpoints, NameID format,
verified domains, and optional organization slug. Domain selection uses only
the catalog's verified-domain index. Authentication identity is always the
signed NameID plus pinned IdP entity and provider IDs; an email attribute is
never an implicit account-link key. `AuthSamlIdentityResolver` is the explicit
application seam for resolving or provisioning users and can later share an
identity mapping with SCIM without coupling the plugins.

The server emits SP metadata and HTTP-POST AuthnRequests, then accepts
HTTP-POST ACS responses. AuthnRequest, RelayState, browser binding, provider
binding, and assertion replay are consumed by one durable atomic store
operation. IdP-initiated SSO is disabled unless a fixed callback is selected.
Final sessions or JWTs, callbacks, lifecycle events, and redirects remain
host-owned.

The client adds only SAML operations:

```dart
const samlClientPlugin = AuthSamlClientPlugin();
final auth = AuthClient(
  baseUrl: Uri.parse('https://api.example.com'),
  plugins: const [samlClientPlugin],
);
final form = await auth.plugins.use(samlClientPlugin).signIn(
  AuthSamlSignInRequest(
    providerId: 'acme',
    callbackUrl: Uri(path: '/dashboard'),
  ),
);
// Submit form.fields to form.destination using an HTML POST form.
```

Routed intentionally does not include a built-in XMLDSig verifier yet. The
maintained Dart `xml_crypto` package supports useful primitives, but its public
API leaves exact signed-node binding to callers, defaults to SHA-1, and does
not advertise browser support. Production applications must provide
`AuthSamlAssertionVerifier` and run
`AuthSamlVerifierConformanceSuite` with real signed and hostile fixtures.
Dynamic connection administration, OIDC enterprise connections, encrypted
assertions, single logout, and group or role provisioning are not in this
slice.

## Optional last-authentication-method plugin

Install this plugin only when the sign-in UI needs to remember which method a
browser used most recently. It stores an allowlisted method ID in an expiring,
HMAC-protected cookie; it never stores a user ID, provider payload, credential,
or token:

```dart
final lastMethod = AuthLastAuthenticationMethodPlugin<MyRequestContext>(
  signingKey: lastMethodSigningKey,
  browserStore: myLastMethodBrowserStore,
  policy: AuthLastAuthenticationMethodPolicy(
    allowedMethods: const {
      AuthLastAuthenticationMethodId.credentials,
      AuthLastAuthenticationMethodId.passkey,
    },
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: [CredentialsProvider()],
  store: authStore,
  storeMode: AuthStoreMode.durable,
  productionBoundary: productionBoundary,
  plugins: [lastMethod],
);
```

The host updates the cookie only after successful session or JWT issuance and
clears it on sign-out and account deletion. Client access is independently
opted in with `AuthLastAuthenticationMethodClientPlugin`; the HttpOnly cookie
itself is never exposed.

## Optional username plugin

Username-first authentication is opt-in and keeps its client API separately
selectable. The server plugin owns normalization and treats values containing
`@` only as email identifiers, avoiding ambiguous username fallback:

```dart
final usernamePlugin = UsernamePlugin<MyRequestContext>(
  identifierPolicy: AuthUsernameIdentifierPolicy(
    minimumLength: 3,
    maximumLength: 32,
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: [CredentialsProvider()],
  store: authStore,
  storeMode: AuthStoreMode.durable,
  productionBoundary: productionBoundary,
  plugins: [usernamePlugin],
);
```

Install only the matching client plugin when the application needs username
registration or sign-in:

```dart
const usernameClient = AuthUsernameClientPlugin();
final auth = AuthClient(
  baseUrl: Uri.parse('https://api.example.com/auth'),
  plugins: const [usernameClient],
);

await auth.plugins.use(usernameClient).signIn(
  identifier: 'ada',
  password: password,
);
```

## Optional two-factor plugin

Compose `TwoFactorPlugin` when an application needs TOTP and recovery codes:

```dart
final twoFactor = TwoFactorPlugin<void>(
  store: myTwoFactorStore,
  challengeStore: myTwoFactorChallengeStore,
  pendingRecoveryStore: myPendingRecoveryStore,
  trustedDeviceStore: myTrustedDeviceStore,
  stepUpStore: myStepUpStore,
  secretProtector: mySecretProtector,
);
```

The plugin owns enrollment verification, TOTP validation, lockout state,
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

## Optional FIDO metadata trust evaluation

`FidoMetadataDownloader` is an opt-in MDS 3.1.1 client. It accepts only HTTPS,
follows a bounded number of same-origin redirects, bounds response bodies and
headers, gives connect + headers + full body one `perRequestTimeout` budget,
and gives the complete multi-hop refresh one non-resetting
`totalRefreshTimeout` budget. It uses ETag validators, rejects stale or foreign
304 cache state, and requires every downloaded blob number to increase. Its
built-in ES256/RS256 verifier terminates at an exact pinned trust anchor and
validates certificate signatures, names, validity, CA constraints, key usage,
path length, supported critical extensions, and metadata-signing extended key
usage.

Certificate revocation remains application-owned and fail-closed. The checker
is called for every non-anchor certificate and must return `good`; `revoked`,
`unknown`, exceptions, and timeouts reject the blob. Copy the current MDS trust
anchor from the FIDO Alliance into application-owned DER bytes and keep the
revocation data current:

```dart
final mdsTrust = FidoMetadataPkixTrust(
  trustAnchors: [globalSignR3Der],
  checkRevocation: checkMdsCertificateRevocation,
);
final mds = FidoMetadataDownloader(trust: mdsTrust);

FidoMetadataRefreshResult? cachedMds;
cachedMds = await mds.refresh(previous: cachedMds);

final metadata = FidoMetadataWebAuthnTrustEvaluator(blob: cachedMds.blob);
final passkeys = WebAuthnPlugin<MyRequestContext>(
  provider: WebAuthnProvider(
    getUserInfo: resolvePasskeyUser,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'example.com',
      name: 'Example',
      origin: 'https://example.com',
    ),
  ),
  attestationTrustPolicy: metadata.asWebAuthnTrustPolicy(),
);

// Close the downloader when the application shuts down.
mds.close();
```

The refresh result is immutable in-memory cache state bound to its source and
trust anchors. Persisting and restoring compact blobs is still
application-owned; re-verify restored bytes before use. Remote `x5u`
certificate-chain discovery is intentionally rejected, so the built-in client
accepts the inline `x5c` profile used by the official service. Applications
with a different metadata source can continue to use
`FidoMetadataBlobLoader` with an application-owned `FidoMetadataJwsVerifier`.

## Optional admin plugin

Administrative APIs are opt-in. Create a plugin-owned admin store over the
same core auth store, then include `AdminPlugin` in `AuthOptions.plugins`:

```dart
final authStore = InMemoryAuthStore();
final adminStore = InMemoryAuthAdminStore(authStore);

final admin = AdminPlugin<MyRequestContext>(
  store: adminStore,
  options: const AuthAdminOptions(
    adminRoles: {'admin'},
    adminUserIds: {'bootstrap-user-id'},
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: providers,
  store: authStore,
  storeMode: AuthStoreMode.ephemeral,
  plugins: [admin],
);
```

`adminUserIds` is a bootstrap mechanism; normal administrators are recognized
from authoritative global user roles. The default `admin` role can manage
users and sessions but cannot impersonate another administrator. Grant the
separate `user:impersonate-admins` permission only through an explicit custom
role. Self-ban, self-delete, self-impersonation, and removal of your own admin
access are rejected.

The plugin supplies user creation/list/get/update, role and password changes,
bans, session listing/revocation, hard deletion, permission checks, and
server-session impersonation. Email, password, and role changes, plus ban and
disable operations, revoke all target server sessions and rotate the target
JWT version. Revoking all sessions also rotates the JWT version; revoking one
server session cannot revoke one already-issued JWT. Active bans are checked
before two-factor challenges, session issuance, and session reuse.

`AuthAdminStore.execute` accepts typed commands rather than independent write
callbacks. A durable implementation must reload the administrator and evaluate
the command's exact resource/action requirements after entering its backend
transaction. It must then update the same records exposed through `AuthStore`,
preserve normalized email uniqueness and the last effective administrator,
and commit sensitive state, credential, server-session, and JWT-version changes
together with a secret-free operation/initiator/target audit fact. Role-based
administrators keep only their configured permissions;
only IDs in `adminUserIds` receive the synthesized bootstrap `admin` role.

Hard deletion continues through the backend-owned deletion coordinator and
must include credentials, provider accounts, tokens, sessions, and every
composed user-owned plugin namespace. Use `AuthAdminOptions.validateDeletion`
to reject application invariants such as deleting the last owner of an
organization. Run `AuthAdminStoreConformanceSuite` from
`package:server_auth/testing.dart` against every durable adapter, including a
test-only transaction fault point. `InMemoryAuthAdminStore` and
`InMemoryAuthStore` are for tests and local development, not production
persistence.

The in-memory Admin store discovers composed user-data deletion contributors
when plugin topology freezes. With `OrganizationPlugin`, it automatically
enforces last-owner protection and clears organization/team membership data.
Durable adapters must provide the equivalent cross-plugin transaction.

Impersonation consumes the current server session inside the admin command, so
start and stop are single-use even under concurrent requests. Routed creates
the replacement session afterward. If host session creation fails, the old
session stays revoked and the caller must sign in again; the plugin does not
claim an exactly-once cross-host transaction. Application hooks, lifecycle
events, and audit delivery also run after commit and can return warnings.
Revocation contributed by separately persisted plugins cannot share the core
admin transaction; ban and disable therefore advertise `nonAtomic` semantics
and fail visibly if that follow-up revocation is incomplete.

The admin client is installed explicitly and shares the host transport:

```dart
final transport = AuthClientTransport(
  baseUrl: Uri.parse('https://example.com'),
  cookieStore: myCookieStore,
);
final auth = AuthClient(
  baseUrl: Uri.parse('https://example.com'),
  transport: transport,
  plugins: const [AuthAdminClientPlugin()],
);
final admin = auth.plugins.use(const AuthAdminClientPlugin());
```

The shared transport owns cookies, bearer tokens, CSRF refresh, timeouts, and
bounded error parsing. Mutation results retain committed data and expose typed
warnings when an after-commit hook or audit sink fails.

## Optional organization plugin

Organizations are opt-in. Nothing is registered unless an
`OrganizationPlugin` is included in `AuthOptions.plugins`:

```dart
final organizations = OrganizationPlugin<MyRequestContext>(
  store: myOrganizationStore,
  options: const AuthOrganizationOptions(
    teams: AuthOrganizationTeamsOptions(enabled: true),
    dynamicRoles: true,
  ),
);

final options = AuthOptions<MyRequestContext>(
  providers: providers,
  store: myAuthStore,
  productionBoundary: productionBoundary,
  plugins: [organizations],
);
```

The plugin owns organizations, memberships, email-bound invitations,
organization-scoped permissions, dynamic roles, teams, typed lifecycle hooks,
redacted audit events, and post-commit warnings. Organization roles remain
separate from global `AuthPrincipal.roles`.

`AuthOrganizationStore` is a logical persistence contract. High-risk writes
also require `AuthOrganizationAtomicMutationStore`: the store rechecks actor,
target, invitation, role, and team snapshots inside the same transaction that
enforces capacity, uniqueness, last-creator, and cascade invariants. Production
adapters should run `verifyAuthOrganizationStoreOwnershipConformance` to prove
contention, deterministic replay, and rollback behavior. The contract contains
no SQL, D1 bindings, table names, migrations, or query builders.

Organization, invitation, role, team, and team-member creation requires a
caller-generated `idempotencyKey` (8-128 ASCII letters, digits, `.`, `_`, `:`,
or `-`). It is a non-secret retry/correlation value. The store binds it exactly
to the organization, actor, operation, and request fingerprint and returns the
original immutable result on a matching retry; conflicting reuse fails closed.
Pre-commit transformation hooks run outside the durable transaction and may be
called again when a client retries. A store-confirmed replay skips delivery,
post-commit hooks, and audit/event sinks; failures from those callbacks on the
first commit surface warnings rather than rolling back durable state.

Teams and dynamic roles are separately disabled by default. Default limits
match the Better Auth benchmark: 100 members, 100 pending invitations, and a
48-hour invitation lifetime. A built-in opaque ID generator is used unless an
application supplies one. Custom non-opaque invitation IDs require a verified
session email before they can be acted upon.

The organization client shares `AuthClientTransport` for cookies, bearer
tokens, CSRF refresh, timeouts, redirects, and bounded error parsing:

```dart
final transport = AuthClientTransport(
  baseUrl: Uri.parse('https://example.com'),
  cookieStore: myCookieStore,
);
final auth = AuthClient(
  baseUrl: Uri.parse('https://example.com'),
  transport: transport,
  plugins: const [AuthOrganizationClientPlugin()],
);
final organization = auth.plugins.use(const AuthOrganizationClientPlugin());
final created = await organization.create(
  name: 'Acme',
  slug: 'acme',
  idempotencyKey: requestId,
);
```

`AuthOrganizationClient` keeps active organization/team selection locally and
sends the selected IDs explicitly. This works with JWTs without silently
reissuing tokens; Routed server sessions may additionally persist the same
selection as a convenience.

## Optional API-key plugin

Compose `AuthApiKeyPlugin` for service-client credentials:

```dart
final apiKeys = AuthApiKeyPlugin<MyRequestContext>(
  store: myApiKeyStore,
  sessionExchangeEnabled: true, // Only when API keys may create sessions.
);

final options = AuthOptions<MyRequestContext>(
  store: myAuthStore,
  providers: providers,
  productionBoundary: productionBoundary,
  plugins: [apiKeys],
);
```

Only a digest is persisted. The raw key is returned once when it is created or
rotated; listing returns metadata, scopes, expiry, last-use, and revocation
state. Production applications should provide a durable `AuthApiKeyStore` and
implement its atomic touch, revoke, and rotate operations transactionally.
Routed can additionally expose `POST /auth/api-keys/exchange` when
`sessionExchangeEnabled` is true. It accepts the API key from an auth header
and creates a normal server-side session; it is disabled by default.

## Optional OAuth/OIDC provider mode

Applications acting as an authorization server install
`OAuthProviderModePlugin` with one authoritative authorization-code exchange
store. The exchange store owns both the authorization-code and access-token
stores, which prevents provider mode from composing a code-consume operation
with a separate token write.

```dart
import 'package:server_auth/server_auth.dart';

final exchangeStore = InMemoryOAuthAuthorizationCodeExchangeStore();

final oauthProvider = OAuthProviderModePlugin<MyRequestContext>(
  clientStore: InMemoryOAuthClientStore(),
  authorizationCodeExchangeStore: exchangeStore,
  options: const OAuthProviderModeOptions(
    supportedGrantTypes: ['authorization_code'],
  ),
);
```

The in-memory exchange store is for tests and local development. A production
adapter implements `OAuthAuthorizationCodeExchangeStore` with one backend
transaction that revalidates the code digest, stable authorization ID, client,
redirect URI, S256 verifier, and expiry, consumes the code, and persists the
prepared token-digest record. Run
`verifyOAuthAuthorizationCodeExchangeStoreConformance` from
`package:server_auth/testing.dart` in every durable adapter test suite.

Raw authorization codes, access tokens, and refresh tokens are delivery-only.
They are generated before commit and never enter persistence, diagnostics, or
replay state. If the transaction commits but the HTTP response is lost, the
client must restart authorization: the server reports `invalid_grant` and does
not mint a second grant or persist raw tokens to replay the response.

The token endpoint advertises atomic, single-use mutation semantics only when
authorization code is its sole grant. A mixed endpoint remains explicitly
non-atomic and unguarded because client credentials, refresh, or contributed
grants cannot share one truthful replay contract.

## Auth runtime and typed stores

Integrations compose an `AuthRuntime` from typed domain stores and server
plugins. `AuthStore` is the required persistence boundary; there is no legacy
adapter bridge or implicit fallback:

```dart
final options = AuthOptions<void>(
  providers: [google],
  store: InMemoryAuthStore(), // Use a database-backed AuthStore in production.
  storeMode: AuthStoreMode.ephemeral,
  plugins: [MyAuthServerPlugin()],
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

`AuthOptions` defaults to production posture and rejects an unannotated
`InMemoryAuthStore`. If ephemeral storage is intentional for a test or local
demo, set `storeMode: AuthStoreMode.ephemeral`; that selects coherent local
cookie, browser, and account defaults. Production construction and runtime
boot validate durable persistence, the HTTPS/proxy boundary, browser policy,
cookies, and JWT secret strength automatically.

Authentication rate limits are configured as a typed policy on
`AuthOptions.rateLimiter`. The policy receives the operation, provider ID,
framework context, and optional login identifier; it never receives a
password, OAuth code, bearer token, or verification token. Routed invokes the
policy before its built-in auth operations and custom callback providers:

```dart
final options = AuthOptions<MyRequestContext>(
  providers: providers,
  store: myStore,
  productionBoundary: productionBoundary,
  rateLimiter: MyAuthRateLimiter(),
);
```

Return `AuthRateLimitDecision.block(retryAfter: ...)` to produce a stable
`rate_limited` failure in an adapter. The adapter owns the client identity
used for the limit, including any trusted-proxy policy.

Plugins receive the shared `AuthStore` during configuration. They own one
auth concern at a time and may contribute portable endpoint, logical schema,
typed-client, and namespaced rate-limit descriptors. The registry rejects
duplicate plugin IDs and endpoint method/path pairs, then freezes the plugin
topology after runtime boot.

For Routed applications, use `routed_auth` and a typed `AuthDeployment`; its
service provider, option binding, and engine configuration keep the runtime
posture and proxy boundary together. `server_auth` itself never registers
framework providers.

## Using with Shelf

Use `shelf_auth` for Shelf-specific middleware while keeping providers and
auth contracts in `server_auth`.

```yaml
dependencies:
  server_auth: ^0.2.0
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
