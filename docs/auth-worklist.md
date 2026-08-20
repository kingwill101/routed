# Routed Auth Worklist

This is the implementation checklist for bringing `server_auth` and
`routed_auth` closer to a production-ready, Better Auth-level product while
preserving Routed's typed Dart and framework-independent architecture.

Better Auth is a capability and developer-experience benchmark for this work,
not a dependency or an integration target. `server_auth` should provide these
capabilities through native Dart APIs, contracts, stores, and client tooling.
Any external Better Auth interoperability is optional and must not shape the
core auth model.

The work is intentionally split between framework-agnostic capabilities in
`server_auth` and HTTP/session integration in `routed_auth`.

> Status refreshed: 2026-08-20. Checked items describe capabilities currently
> present in the workspace; unchecked items are the remaining product or
> validation work.

## Architecture foundation

- [x] Introduce typed user, credential, account, session, and verification
  token store contracts in `server_auth`.
- [x] Make `AuthStore` the only auth persistence boundary and remove the flat
  adapter compatibility API.
- [x] Add `AuthRuntime` and `AuthServerPlugin` composition with duplicate-ID checks.
- [x] Expose the composed runtime through `AuthManager` and
  `AuthServiceProvider`.
- [x] Let plugins contribute endpoint descriptors, hooks, schemas, rate-limit
  rules, and typed client operations without editing a central route switch.
- [x] Define paired server/client plugin contracts so a plugin can expose its
  persistence, routes, response models, client methods, and conformance tests
  as one public capability.
- [x] Migrate the existing credentials, email, OAuth, and session flows from
  direct adapter calls to their domain stores.

## P0: production safety

- [x] Keep `InMemoryAuthStore` explicitly limited to tests and local
  development; unannotated use fails at `AuthOptions` construction and
  adapters can reject annotated ephemeral storage during production boot.
- [x] Add a `PasswordHasher` contract with a PointyCastle-backed Argon2id
  implementation, versioned parameters, rehash-on-login support, and
  constant-time password verification.
- [x] Add a typed length-first password policy that bounds verifier input and
  rejects weak or oversized passwords in the built-in credentials flow.
- [x] Normalize built-in email identifiers before credential lookup,
  registration, and verification-token persistence.
- [x] Treat unverified OAuth email claims as untrusted for account linking,
  local email persistence, and external account identity selection.
- [x] Add explicit password-credential records instead of storing passwords in
  `AuthUser.attributes`; the built-in flow hashes and verifies through the
  configured `PasswordHasher`.
- [x] Define a persistent session model containing a hashed session token,
  user ID, creation time, expiry, last-used time, revocation time, IP address,
  user agent, and authentication method.
- [x] Connect routed session issuance and resolution to `AuthSessionStore` so
  revocation and expiry are enforced on every authenticated request.
- [x] Make session creation, rotation, refresh, and revocation atomic at the
  typed store boundary.
- [x] Make verification-token consumption atomic at the typed store boundary;
  in-memory storage persists only SHA-256 token digests and rejects replay.
- [x] Add the typed password-reset token boundary with hashed, expiring,
  per-user-invalidated, atomically consumed tokens.
- [x] Add framework-agnostic password-reset issuance and replacement helpers
  that update password credentials and revoke active server sessions.
- [x] Add auth-specific rate-limit contracts for sign-in, registration,
  verification, and callback endpoints. Routed invokes the contract before
  built-in flows and custom callbacks, and `RoutedAuthRateLimiter` adapts the
  existing `server_rate_limit` service; password-reset and passkey actions will
  use the same contract when those plugins land.
- [x] Use Routed's explicit trusted-proxy/client-IP policy for auth rate-limit
  keys and persisted session metadata; auth does not read forwarded headers
  directly. Broader proxy configuration ergonomics remain a core concern.
- [x] Add browser protections beyond CSRF tokens to the Routed adapter. Safe
  default Routed session cookies and CSRF protections now pair with typed
  trusted-origin policy, strict `Origin` validation, and Fetch Metadata checks
  on state-changing auth routes. Other framework adapters and validation of
  externally supplied session stores remain follow-up work.
- [x] Keep Routed auth HTTP failures generic while detailed causes remain
  available to Routed's internal error hooks; other framework adapters must
  adopt the same boundary.

## P1: complete the account lifecycle

- [ ] Finish the email/password account lifecycle. Registration, sign-in,
  duplicate-account handling, email verification, and opt-in
  disabled/unverified-account policy now exist; email change, deletion, and
  complete lifecycle coverage remain.
- [x] Add Routed password-reset request and confirmation routes with generic
  account responses, rate limits, application-owned notification delivery,
  server-session revocation, and JWT version rotation.
- [x] Add per-user JWT session versioning and revocation. Password reset and
  password change rotate the version, and Routed JWT middleware rejects stale
  tokens.
- [x] Add an authenticated password-change flow with reauthentication,
  server-session revocation, trusted-device revocation, and JWT version
  rotation.
- [ ] Add email change, account deletion, and linked-account list/link/unlink
  operations with reauthentication where needed. Email-change request and
  confirmation plus authenticated account listing, unlinking, and deletion
  are now implemented; typed tombstone retention/purge is available, while
  broader credential fallback rules remain.
- [x] Add a first-class server-session management API: list current sessions
  with device metadata, revoke one session, revoke all other sessions, and
  rotate credentials after sensitive changes. JWT session management remains a
  separate revocation/versioning capability.
- [x] Add client session helpers for current-session metadata, session listing,
  session revocation, and device/session labels.
- [x] Add typed WebAuthn challenge and authenticator stores with one-time
  challenge consumption, credential uniqueness, and compare-and-set counter
  updates.
- [x] Add `none`-attestation/ES256 registration and assertion verification with
  exact origin/RP-ID binding, user-presence checks, and replay protection.
- [x] Add packed self/certificate attestation with ES256 and RS256 plus FIDO U2F
  attestation, including browser DER signatures and bounded certificate/chain
  validation.
- [x] Add strict Android Key, Apple Anonymous, and TPM 2.0 attestation with
  challenge or nonce binding, authenticator-key matching, certificate
  validation, and fail-closed malformed-input handling.
- [x] Expose the registration, assertion, listing, and deletion contracts
  through the typed plugin registry, Routed routes, and `AuthClient`.
- [ ] Finish the broader WebAuthn subsystem. Session issuance, passkey rename,
  Ed25519, Android Key, Apple Anonymous, TPM 2.0, and an explicit
  accept/reject/downgrade attestation-root trust policy are implemented, but
  FIDO metadata and deprecated attestation formats are still pending.
- [x] Add an optional native `TwoFactorPlugin` with TOTP enrollment
  verification, protected-secret and typed-store boundaries, recovery-code
  hashing and atomic one-time consumption, lockout handling, disablement, and
  recovery-code regeneration.
- [x] Add short-lived, single-use pending credential sign-in challenges that
  require TOTP verification before session issuance.
- [x] Add short-lived, session-bound step-up verification proofs and a helper
  for sensitive-route enforcement.
- [x] Add typed client helpers for step-up verification and revocation.
- [x] Add typed client methods and Routed routes for two-factor enrollment,
  TOTP verification, backup-code generation/use, status, and disablement.
- [x] Add typed client challenge exceptions and pending TOTP/recovery-code
  challenge completion methods.
- [x] Add typed expiring trusted-device handling, cookie issuance, and
  revoke-all support.
- [x] Add pending recovery-code flows with an atomic challenge/recovery
  transaction boundary.
- [x] Add API-key issuance, hashing, metadata, expiry, revocation, scopes,
  built-in lifecycle rate limits, and atomic touch/revoke/rotate operations.
  Add an opt-in, header-only exchange into a server-side session.
- [x] Add typed client methods for API-key creation, listing, rotation,
  revocation, secure one-time display of the raw key, and opt-in session
  exchange.

## P1: authorization and tenancy

- [x] Add first-class organizations/tenants, memberships, invitations, and
  organization-scoped roles.
- [x] Add administrative user/session/account management APIs with explicit
  authorization checks and audit events.
- [x] Extend the existing RBAC, policy, and Haigate APIs to support tenant
  context and resource ownership without relying on global role strings.
- [x] Add an OAuth/OIDC provider mode for applications acting as an identity
  provider, with hashed one-time authorization codes, PKCE, grants, refresh,
  introspection, userinfo, discovery, asymmetric ID-token signing, and JWKS.

## P2: Dart developer experience and platform integration

- [ ] Complete typed persistence adapters for the supported Routed storage
  paths. `routed_auth_cloudflare` now supplies a typed, migrated D1 `AuthStore`
  and passes local conformance/contention tests; a deployed live-D1 run, broader
  SQL adapters, and a D1-compatible plugin-deletion transaction remain open.
  The deletion redesign will replace callback-based mutation with immutable,
  backend-bound plugin deletion plans executed with core deletion by one
  transaction coordinator; foreign persistence domains must fail closed.
- [x] Define a stable public adapter conformance suite that can run against
  every persistence implementation through `package:server_auth/testing.dart`.
- [x] Add a small, typed Dart client contract for browser/mobile auth calls
  without requiring application code to duplicate route and cookie
  conventions.
- [x] Split the client contract into typed plugin modules while preserving a
  shared transport, cookie store, CSRF policy, error model, and request
  lifecycle.
- [x] Add typed local-development, secure-session, JWT API, and service API-key
  deployment presets with explicit production boundaries, plus Routed binding
  helpers for options, provider setup, and proxy-aware engine configuration.
- [x] Make plugins contribute their routes, schemas, hooks, and rate-limit
  rules through the public composition API instead of requiring consumers to
  edit central route switches.
- [x] Add a CLI/device authorization flow for limited-input clients, including
  device-code issuance, browser approval, polling, denial, expiry, and
  client-side backoff semantics.
- [x] Add OpenAPI 3.1 endpoint and model generation for core auth routes and
  composed plugin routes, with generated-client compatibility tests.
- [x] Publish framework-neutral store and runtime conformance APIs for durable
  adapters and IO, Node, and Fetch hosts.
- [ ] Add reusable provider fixtures and end-to-end helpers for plugin-specific
  flows beyond the shared runtime conformance contract.
- [x] Update the package READMEs and examples only after the public APIs and
  security defaults settle.

## Longer-term plugin-inspired backlog

These capabilities are useful product benchmarks, but should follow the core
account, session, client, and plugin contracts above:

- [x] Add email OTP as a separate one-time-code flow alongside magic links.
- [x] Add phone-number authentication with provider-owned delivery and
  verification boundaries.
- [x] Add username-first authentication and explicit identifier policy.
- [x] Add anonymous/guest sessions with safe account upgrade/linking rules.
- [ ] Track the last successful authentication method without storing secrets.
- [x] Add captcha and breached-password checks as opt-in security plugins.
- [ ] Add SSO/SAML and SCIM integrations when enterprise tenancy requirements
  justify them.

## Optional: interoperability

These capabilities may help applications migrate from or coexist with other
authentication systems, but they are not part of the core `server_auth`
product direction and must not introduce an external-auth dependency into the
native auth model.

- [ ] Add an optional interoperability path for consuming external Better Auth
  or OIDC identity through JWT verification or OAuth introspection.
- [ ] Keep external identity resolution separate from `AuthStore`, local
  account provisioning, and local session ownership.

## Active security-audit remediation

- [ ] Route every plugin-authenticated identity through host-owned session
  issuance. WebAuthn JWT authentication must not report success without a
  usable session, and phone, anonymous, email-OTP, username, and WebAuthn must
  all honor the configured JWT body-token policy, callbacks, and events.
- [x] Require browser-origin protection for anonymous and email-OTP sign-in
  while retaining explicit native-client behavior.
- [ ] Derive bounded, non-secret rate-limit identifiers from typed plugin
  requests, use each operation namespace as provider identity, and preserve
  that metadata through the Routed rate-limit adapter.
- [x] Prevent public WebAuthn authentication options from revealing enrollment
  or credential IDs, and validate presented certificate chains against
  out-of-band trust anchors when the root is omitted from `x5c`.
- [x] Start captcha replay retention after successful provider verification so
  slow providers cannot make an accepted token immediately reusable.
- [ ] Make plugin conformance consume actual installed client operation and
  codec contracts instead of comparing only server-declared descriptors.
- [x] Constrain Routed auth deployment binding to `EngineContext` and reject an
  incompatible context at startup instead of silently omitting auth routes.
- [ ] Replace callback-based hard deletion with backend-bound deletion plans
  executed with core deletion by one storage transaction. Include anonymous,
  email-OTP, API-key, WebAuthn, two-factor, and organization-owned state, and
  fail closed when contributors use another persistence domain.
- [x] Make organization last-owner checks transactional across removal,
  demotion, role replacement, leave, and user-deletion paths, with reusable
  durable-store conformance and contention coverage.
- [ ] Retain a non-personal revocation receipt so explicit user-ID reuse cannot
  reactivate credentials or JWTs after hard deletion.

## Required test coverage

- [x] Property-test public serialization to prove secrets, credentials,
  session tokens, OAuth tokens, and nested sensitive keys never escape.
- [x] Redact provider credentials, account tokens, JWT sessions, user/profile
  attributes, credentials, and session payloads before publishing auth events.
- [x] Property-test redirect, provider ID, callback state, CSRF, cookie, and
  header inputs for injection, truncation, and normalization edge cases. The
  Routed property suite covers HTTP handling and `server_auth` now has a
  framework-agnostic redirect-origin property suite.
- [x] Add stateful/property tests for session rotation, concurrent session
  refresh, and revocation; concurrent verification-token replay is covered by
  the server-auth token-store tests.
- [x] Add stateful tests for replayed OAuth and passkey challenges through their
  atomic challenge stores, including counter replay and malformed ceremony
  inputs.
- [x] Enforce provider-account uniqueness at the account-link boundary and
  reject cross-user OAuth account-link conflicts in both OAuth helper paths.
- [x] Reject empty or duplicate provider IDs and incomplete user/account
  identities before they enter auth route or persistence namespaces.
- [x] Validate session persistence identities and lifetimes, and enforce
  server-time expiry checks during in-memory session touch.
- [x] Make in-memory credential registration reject malformed records and
  preserve identifier uniqueness under concurrent attempts.
- [x] Preserve user email uniqueness on in-memory create/update and avoid
  reporting rejected OAuth profile updates as persisted.
- [x] Freeze configured provider lists after runtime construction so provider
  namespaces cannot be mutated without revalidation.
- [x] Prevent the callback-backed test store from being used as auth options or
  runtime persistence.
- [x] Reject non-positive OAuth request and email-verification lifetimes during
  provider construction.
- [x] Require every successful credential, email, OAuth, and custom callback to
  resolve a non-empty canonical user identity before session issuance.
- [x] Convert malformed or unrepresentable JWT/OAuth timestamps into bounded
  authentication failures rather than uncaught date-range exceptions.
- [x] Hash in-memory remember-me tokens and reject blank token generators,
  empty principals, and non-positive remember-token lifetimes.
- [x] Compare CSRF and OAuth state secrets through fixed-width digest checks.
- [x] Consume remember-me tokens atomically during hydration before rotation,
  with concurrent replay coverage.
- [x] Make asserted-email OAuth and email sign-in user creation atomic at the
  typed store boundary.
- [x] Cover the typed Dart client contract for CSRF, cookies, sessions,
  providers, OAuth redirects, and bounded auth errors.
- [x] Add negative/configuration tests for weak password registration, missing
  trusted-proxy configuration, explicit CSRF opt-out behavior, safe cookie
  defaults with a local insecure opt-out, and accidental in-memory persistence
  in production configuration.
- [x] Run the public auth runtime contract through native `routed_io`, portable
  and native `routed_node`, and native Cloudflare Fetch request paths.
- [ ] Run the D1 conformance harness against a deployed or remote-bound
  Cloudflare database; compilation and local emulation are not live validation.
- [x] Keep the current auth packages, host adapter integrations, and public
  conformance suites analyzer-clean and passing on `master`.

## Definition of done

- [x] Audit every production path to ensure plaintext passwords are neither
  persisted nor compared directly. Built-in registration, sign-in, reset,
  change, administration, email-change, and deletion paths all use the
  configured password hasher.
- [ ] Every state-changing auth operation has an explicit persistence and
  replay-safety story.
- [ ] Every auth endpoint has documented authentication, CSRF/origin,
  rate-limit, redirect, and error semantics.
- [x] The shared credentials/session runtime contract is verified through
  `routed_io`, native Node, and native Cloudflare Fetch request paths.
- [ ] Every advertised plugin flow has matching end-to-end coverage across its
  applicable host runtimes.
- [ ] Security-sensitive defaults are safe without requiring users to discover
  undocumented configuration switches.
