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

> Status refreshed: 2026-08-19. Checked items describe capabilities currently
> present in the workspace; unchecked items are the remaining product or
> validation work.

## Architecture foundation

- [x] Introduce typed user, credential, account, session, and verification
  token store contracts in `server_auth`.
- [x] Make `AuthStore` the only auth persistence boundary and remove the flat
  adapter compatibility API.
- [x] Add `AuthRuntime` and `AuthFeature` composition with duplicate-ID checks.
- [x] Expose the composed runtime through `AuthManager` and
  `AuthServiceProvider`.
- [x] Let features contribute endpoint descriptors, hooks, schemas, rate-limit
  rules, and typed client operations without editing a central route switch.
- [x] Define paired server/client feature contracts so a feature can expose its
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
  use the same contract when those features land.
- [x] Use Routed's explicit trusted-proxy/client-IP policy for auth rate-limit
  keys and persisted session metadata; auth does not read forwarded headers
  directly. Broader proxy configuration ergonomics remain a core concern.
- [ ] Expand browser protections beyond CSRF tokens where appropriate. Safe
  default Routed session cookies and CSRF protections cover state-changing
  Routed auth routes; trusted-origin policy, `Origin` validation, Fetch
  Metadata checks, broader adapter coverage, and validation of externally
  supplied session stores remain.
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
  are now implemented; tombstone retention and broader credential fallback
  rules remain.
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
- [x] Expose the registration, assertion, listing, and deletion contracts
  through the typed feature registry, Routed routes, and `AuthClient`.
- [ ] Finish the broader WebAuthn subsystem: support additional attestation and
  COSE algorithms. Routed now issues a server-side session after a verified
  assertion when that strategy is configured, and passkeys can be renamed
  through the owner-checked store, feature endpoint, and client API.
- [x] Add an optional native `TwoFactorFeature` with TOTP enrollment
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
- [ ] Add an OAuth/OIDC provider mode if Routed applications need to act as an
  identity provider, not only consume external providers.

## P2: Dart developer experience and platform integration

- [ ] Add typed persistence adapters for the supported Routed storage paths,
  including schema/migration guidance for SQL and D1.
- [ ] Define a stable adapter conformance suite that can run against every
  persistence implementation.
- [x] Add a small, typed Dart client contract for browser/mobile auth calls
  without requiring application code to duplicate route and cookie
  conventions.
- [x] Split the client contract into typed feature modules while preserving a
  shared transport, cookie store, CSRF policy, error model, and request
  lifecycle.
- [ ] Add ergonomic typed configuration builders or presets for common auth
  deployments while keeping security-sensitive defaults explicit and safe.
- [x] Make features contribute their routes, schemas, hooks, and rate-limit
  rules through the public composition API instead of requiring consumers to
  edit central route switches.
- [ ] Add a CLI/device authorization flow for limited-input clients, including
  device-code issuance, browser approval, polling, denial, expiry, and
  client-side backoff semantics.
- [ ] Add OpenAPI 3.1 endpoint and model generation for core auth routes and
  composed feature routes, with generated-client compatibility tests.
- [ ] Add reusable auth test utilities for route bootstrapping, cookie/session
  handling, provider fixtures, and end-to-end feature flows.
- [x] Update the package READMEs and examples only after the public APIs and
  security defaults settle.

## Longer-term plugin-inspired backlog

These capabilities are useful product benchmarks, but should follow the core
account, session, client, and feature contracts above:

- [ ] Add email OTP as a separate one-time-code flow alongside magic links.
- [ ] Add phone-number authentication with provider-owned delivery and
  verification boundaries.
- [ ] Add username-first authentication and explicit identifier policy.
- [ ] Add anonymous/guest sessions with safe account upgrade/linking rules.
- [ ] Track the last successful authentication method without storing secrets.
- [ ] Add captcha and breached-password checks as opt-in security features.
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
- [ ] Run integration tests for `routed_io`, `routed_node`, and Cloudflare
  Fetch/D1-compatible adapters where the capability is supported.
- [ ] Keep the full auth workspace, adapter integration, and conformance test
  suites warning-free. The current `server_auth` and `routed_auth` suites and
  analyzer pass locally; adapter coverage remains.

## Definition of done

- [ ] Audit every production path to ensure plaintext passwords are neither
  persisted nor compared directly. The built-in credential path uses the
  configured password hasher.
- [ ] Every state-changing auth operation has an explicit persistence and
  replay-safety story.
- [ ] Every auth endpoint has documented authentication, CSRF/origin,
  rate-limit, redirect, and error semantics.
- [ ] The same auth behavior is verified through both `routed_io` and
  `routed_node` where the feature is advertised.
- [ ] Security-sensitive defaults are safe without requiring users to discover
  undocumented configuration switches.
