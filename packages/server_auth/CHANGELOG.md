## Unreleased

- Rename auth capability APIs to server plugins and add an opt-in typed client plugin
  registry so applications select only the client APIs they use.
- Keep the shared auth transport public while hiding the transport-backed core
  implementation from the package umbrella library.
- Add central authentication-policy helpers for verified-email enforcement and
  disabled, tombstoned, or unavailable accounts. Email verification now marks
  the persisted user before session issuance.
- Include API-key and WebAuthn credential namespaces in the plugin-owned
  account-deletion transaction.
- Issue a normal server-side session after a successful Routed WebAuthn
  assertion, using the same session rotation, policy, and revocation path as
  other authentication methods.
- Extend the typed external-account store with per-user listing and
  owner-checked unlink operations for the account-linking lifecycle.
- Add the digest-backed, one-time email-change token store and an atomic
  owner-scoped email update operation that enforces normalized uniqueness.
- Add typed email-change issuance/confirmation helpers with password
  reauthentication and verified-address marking.
- Add the opt-in `AdminPlugin`, typed atomic admin store, authoritative role
  permissions, bans, session administration, guarded hard deletion,
  server-session impersonation, lifecycle hooks/events, persistence topology,
  and `AuthAdminClient`.
- Add plugin authentication-policy and host session-control contributions so
  portable plugins can block session issuance/reuse and safely replace a
  server-session identity.
- Add owner-checked WebAuthn passkey renaming through the typed store, plugin
  endpoint, and client API.
- Add typed account tombstone and retention-purge capabilities; self-service
  deletion now retains only a stable unavailable user ID and deletion time.

- Added the opt-in typed `WebAuthnPlugin` with digest-at-rest one-time
  challenges, durable authenticator/counter contracts, `none` attestation,
  ES256 assertion verification, exact origin/RP-ID binding, and replay-safe
  compare-and-set counter updates. Broader COSE algorithms and session issuance
  remain follow-up capabilities.
- Make password reset/change fail closed by rotating JWT versions and revoking
  server sessions before replacing credentials.
- Derive `AuthStoreMode` when framework composition replaces the configured
  store, expire client cookies using absolute `Max-Age` deadlines, and cover
  automatic CSRF refresh after stale-session rejection.
- Add the opt-in `OrganizationPlugin`, typed atomic organization store,
  memberships, invitations, scoped permissions, lifecycle hooks, dynamic
  roles, teams, logical persistence descriptors, and typed organization client.
- Add plugin-contributed endpoint/client/schema/rate-limit descriptors,
  immutable runtime topology, namespaced rate-limit operations, and the shared
  public `AuthClientTransport`.
- Add the opt-in `AuthApiKeyPlugin` with digest-at-rest keys, scoped metadata,
  bounded expiry, atomic touch/revoke/rotate storage operations, and one-time
  raw-secret responses.
- Add typed `AuthClient` API-key creation, listing, revocation, rotation, and
  service-client key configuration.
- Add opt-in, header-only API-key exchange into a server-side session.
- Added the optional `TwoFactorPlugin` with RFC 6238 TOTP enrollment,
  protected-secret storage, atomic lockout/recovery-code operations,
  regeneration, disablement, and pending credential sign-in challenges. The
  implementation uses `hashlib` for its maintained HOTP/TOTP core.
- Added expiring trusted-device records with digest-at-rest storage, optional
  post-TOTP issuance, user-bound bypass lookup, and revoke-all support.
- Added an explicit pending-recovery transaction contract and in-memory
  implementation that atomically consumes a recovery code and completes a
  pending sign-in challenge.
- Added short-lived, session-bound step-up proof storage and TOTP verification
  for sensitive-action enforcement.
- Hardened public auth and WebAuthn JSON deserialization against malformed
  roles, attributes, transports, counters, and timestamps; added 500-case
  property coverage for secret sanitization.
- Bounded malformed OAuth profile parsing and mapping failures to the generic
  `profile_invalid` auth-flow error.
- Hardened base32 decoding for TOTP secrets by rejecting malformed padding,
  impossible lengths, and non-zero trailing bits.
- Bounded corrupted persisted TOTP secrets and secret-protector failures to
  the generic invalid-code auth error.
- Bounded OAuth introspection caching to prevent unbounded memory growth from
  distinct bearer tokens.
- Bounded and cleaned up the in-memory OAuth challenge store so repeated
  authorization starts cannot retain expired state indefinitely.
- Bounded and cleaned up the in-memory verification-token store so arbitrary
  email identifiers cannot retain unlimited token digests.
- Bounded and cleaned up the in-memory two-factor challenge, trusted-device,
  and step-up stores so expired or completed records cannot accumulate without
  limit.
- Bounded and cleaned up the default in-memory remember-me store so expired
  tokens cannot accumulate without limit when no durable token store is bound.
- Made recursive public-attribute sanitization cycle-safe and depth-bounded so
  malformed application/provider values cannot overflow auth serialization.
- Moved two-factor recovery-code lockout enforcement into the atomic store
  operation so concurrent invalid attempts cannot race a valid recovery code.
- Expanded public-attribute secret filtering to cover composite token,
  password-reset, JWT, CSRF, session, and secret-bearing key names.
- Bounded remote JWKS, OAuth token, introspection, and userinfo response
  parsing to prevent oversized provider responses from exhausting the process.
- Applied the OAuth response-size bound and configured request timeout to the
  built-in GitHub and Dropbox profile adapters.
- Prevented provider OAuth extension parameters from overriding protocol-owned
  state, redirect, PKCE, and token-exchange fields.
- Applied account-level TOTP lockout to pending sign-in challenges so issuing
  a fresh challenge cannot reset the verification-attempt budget.
- Applied the same account-level lockout to direct recovery-code verification,
  preventing unlimited invalid recovery-code guesses.
- Require a fresh TOTP proof before the public trusted-device issuance API can
  mint a device-bypass token.
- Honor configured TOTP periods during verification instead of assuming the
  default 30-second period.
- Revoke all session-bound step-up proofs when two-factor authentication is
  disabled.
- Revoke plugin-owned trusted-device bypass tokens during password resets and
  password changes.
- Add atomic compare-and-set factor writes for TOTP enrollment activation and
  recovery-code regeneration.
- Preserve sanitized credential-flow context on pending two-factor challenges.
- Bound recovery-code generation attempts so a repeating custom generator cannot
  hang a successful enrollment indefinitely.
- Added an optional browser-bound OAuth callback check for adapters using a
  durable challenge store; unbound callbacks are rejected before challenge
  consumption.
- Added an optional browser-bound email verification check so adapters can
  reject magic-link callbacks that did not originate in the requesting browser.
- Preserve and enforce the `Secure` cookie attribute in `AuthClient` so session
  cookies are never sent over cleartext HTTP.
- Treat every non-positive `Max-Age` cookie as a deletion in `AuthClient`,
  matching browser cookie semantics.
- Revoke and expire an existing remember-me token when a rotating login opts
  out of remember-me, preventing a prior account from being restored later.
- Added the typed `AuthJwtVersionStore` persistence boundary and in-memory
  implementation. Password resets and password changes rotate the version so
  previously issued JWTs can be rejected without storing every token.
- Added protected JWT claim validation hooks for framework integrations.
- Added a typed `AuthClient` for Dart consumers with route-aware auth flows,
  CSRF handling, explicit cookie storage, OAuth redirect handling, and typed
  session/provider/error responses.
- Added framework-independent password-change orchestration with current
  password reauthentication, password-policy validation, and session
  revocation.
- Added typed server-side session-management projections and store operations
  for listing sessions, revoking one session, and revoking all sessions except
  the current session.
- Added the typed `AuthStore` domain persistence boundary and composable
  `AuthRuntime`/`AuthServerPlugin` contracts.
- Breaking: removed `AuthAdapter`, `CallbackAuthAdapter`, and
  `InMemoryAuthAdapter`; `AuthOptions` now requires an `AuthStore`.
- Migrated credential, email, OAuth, and session orchestration to typed domain
  stores with one authoritative verification-token store.
- Hardened verification-token storage with digest-at-rest persistence and an
  atomic `consume` operation that rejects replayed or expired tokens.
- Added a typed password-reset token store with digest-at-rest persistence,
  per-user invalidation, expiry, and atomic single-use consumption. The
  password-reset HTTP delivery remains adapter-owned.
- Added framework-agnostic password-reset helpers that issue and consume
  tokens, replace all password credentials, and revoke the user's active
  server sessions. HTTP delivery and routes remain adapter-owned work.
- Added a typed password-reset delivery request contract so framework
  adapters can send raw one-time tokens without putting them in persistence.
- Added `AuthSessionRecord` and typed session-store operations for hashed-token
  lookup, monotonic touch, revocation, and atomic rotation.
- Replaced plaintext-facing credential store operations with explicit
  `AuthPasswordCredential` records and configured `PasswordHasher` flows.
- Redacted password fields from retained sign-in events and credential
  attribute projections.
- Added a PointyCastle-backed Argon2id `PasswordHasher` with encoded policy
  parameters, constant-time verification, and rehash-on-login signaling.
- Added a typed length-first `PasswordPolicy` that bounds verifier input and
  rejects weak or oversized passwords in the built-in credentials flow.
- Normalized email identifiers at built-in credential and verification-flow
  boundaries to prevent case/whitespace duplicate namespaces.
- Added an atomic user `createOrFindByEmail` store operation and routed
  asserted-email OAuth and email callbacks through it to prevent concurrent
  duplicate-user creation.
- Added bounded public auth error-code sanitization for adapter callback and
  flow responses; diagnostic messages remain internal.
- Hardened shared redirect sanitization to reject embedded URL user-info and
  preserve the rooted-relative or same-origin invariant.
- Require an explicit `AuthStoreMode.ephemeral` annotation for
  `InMemoryAuthStore`, and add production-boot validation hooks for adapters.
- Added typed `AuthRateLimiter` contracts for throttling auth operations
  without exposing passwords, OAuth codes, bearer tokens, or verification
  tokens to limiter implementations.
- Added typed browser-protection options for origin and Fetch Metadata checks
  in framework adapters.
- Hardened OIDC/JWT verification with required claims, issuer and audience
  checks, nonce support, and bounded JWKS requests.
- Sanitized public auth model serialization so secrets and tokens are not
  exposed accidentally; private persistence retains the fields it needs.
- Redacted provider tokens and nested credential-like fields from auth event
  projections, including provider, user, session, profile, and payload
  projections, while preserving private values for persistence and callbacks.
- Require a non-empty `sub` claim when resolving JWT-backed auth sessions.
- Normalize malformed JWKS and signature-library failures to bounded JWT auth
  errors while preserving network timeout behavior.
- Normalize malformed OAuth token, introspection, and user-info responses to
  bounded auth errors, and require token exchanges to return an access token.
- Keep provider-specific user-info failures bounded without embedding upstream
  response bodies in thrown auth errors.
- Bound malformed or unrepresentable JWT and OAuth timestamp claims instead of
  allowing date-range exceptions to escape request handling.
- Added a typed, one-time OAuth challenge store so state, PKCE, nonce, and
  callback values can be consumed atomically instead of relying on session
  read-then-delete behavior.
- Hardened external account linking so provider identities are created
  idempotently, never overwritten across users, and callback conflicts fail
  with a bounded auth-flow error.
- Apply the canonical account-link conflict check in the lower-level OAuth
  sign-in helper as well as the full callback helper.
- Reject empty or ambiguous provider IDs during auth runtime construction, and
  reject incomplete user/account identities at the in-memory persistence and
  OAuth account-link boundaries.
- Validate persisted session identity/lifetime fields and ensure in-memory
  session touch checks wall-clock expiry instead of trusting a caller-supplied
  timestamp.
- Make in-memory credential registration reject malformed records and reserve
  identifiers across concurrent registration attempts.
- Preserve in-memory user email uniqueness on create/update, and never return
  an OAuth user projection as updated when the persistence update rejected it.
- Freeze the configured provider list after `AuthOptions` construction so
  route/provider namespaces cannot be changed behind the runtime's invariants.
- Reject `CallbackAuthStore` from auth options and runtime construction; it is
  intentionally a focused-test utility with unsafe no-op fallbacks.
- Reject non-positive OAuth request and email-verification lifetimes at
  provider construction instead of creating immediately unusable flows.
- Require successful credential, email, OAuth, and custom-callback paths to
  resolve a non-empty canonical user ID before a session can be issued.
- Hash remember-me tokens in the in-memory store, reject blank generated
  tokens and principals, and require positive remember-token lifetimes.
- Use fixed-width digest comparisons for CSRF tokens and OAuth state values.
- Make remember-me hydration consume tokens atomically before rotating them,
  preventing concurrent requests from replaying one cookie.
- Treat provider email claims as authoritative only when `verified` or
  `email_verified` is explicitly true; unverified emails cannot overwrite
  local email identity or become OAuth account IDs.
- Added bounded OAuth and introspection requests, with introspection caching
  disabled by default.
- Remove schema-backed auth provider registries and map-based provider
  materialization; applications now pass typed provider instances directly.
- Remove `AuthConfig.fromMap`; adapters now receive `AuthConfig.defaults()` or
  explicitly constructed typed configuration sections.
- Remove unused auth event configuration and the duplicate root remember-me
  section; remember-me settings now live only on `AuthSessionConfig`.
- Remove map/string guard and gate specification parsers; auth definitions are
  now constructed with their typed constructors.

## 0.1.0

- Initial release of framework-agnostic server authentication runtime.
- Added shared auth models, OAuth flow types, and built-in
  providers extracted from the server ecosystem.
