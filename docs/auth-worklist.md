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

- [x] Complete the email/password account lifecycle: registration, sign-in,
  duplicate-account handling, email verification, opt-in
  disabled/unverified-account policy, password reset/change, email change,
  account deletion, and session/JWT revocation.
- [x] Add Routed password-reset request and confirmation routes with generic
  account responses, rate limits, application-owned notification delivery,
  server-session revocation, and JWT version rotation.
- [x] Add per-user JWT session versioning and revocation. Password reset and
  password change rotate the version, and Routed JWT middleware rejects stale
  tokens.
- [x] Add an authenticated password-change flow with reauthentication,
  server-session revocation, trusted-device revocation, and JWT version
  rotation.
- [ ] Protect linked-account and removable plugin credentials with a typed,
  de-duplicated inventory across password, exact OAuth provider accounts,
  passkeys, phone, email OTP/link, username, opt-in primary API keys, and
  future plugin methods. In-memory removals serialize inventory and mutation
  atomically per user. D1 binds only its authoritative core method stores,
  atomically rechecks the exact OAuth target and fallback in SQL, and records
  mixed external-store topologies without blocking plugin composition; unlink
  then fails closed. D1 now owns the exact API-key store through migration v9
  and bounded WebAuthn challenges, passkeys, counter updates, primary-method
  removal, and hard-deletion cleanup through migration v10. Backend-bound D1
  phone persistence now exists through migration v11, including exact
  phone-aware unlink and primary-method removal with verified projection and
  challenge cleanup. Future plugin stores remain. The host-facing removal
  route and authorization proof still need to require recent original
  authentication or explicit step-up proof rather than merely an active
  session.
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
- [x] Finish the supported WebAuthn subsystem: session issuance, passkey rename,
  Ed25519, Android Key, Apple Anonymous, TPM 2.0, explicit
  accept/reject/downgrade attestation-root trust policy, offline FIDO MDS 3.1.1
  evaluation, and an opt-in bounded HTTPS downloader with built-in ES256/RS256
  JWS and pinned PKIX verification. Deprecated attestation formats and remote
  `x5u` chain discovery remain intentionally unsupported.
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
- [x] Add administrative user/session/account management APIs with typed
  backend-owned commands that revalidate exact custom-role permissions inside
  the transaction, roll core user/credential/session/JWT/admin state back on
  failure, preserve the deletion coordinator, and expose durable-adapter
  conformance. Impersonation consumes source sessions once; replacement-session
  creation and audit delivery remain honest post-commit host boundaries.
- [x] Extend the existing RBAC, policy, and Haigate APIs to support tenant
  context and resource ownership without relying on global role strings.
- [x] Add an OAuth/OIDC provider mode for applications acting as an identity
  provider, with hashed one-time authorization codes, PKCE, grants, refresh,
  introspection, userinfo, discovery, asymmetric ID-token signing, and JWKS.
- [x] Replace split provider-mode authorization-code consumption and token
  persistence with a typed backend-owned atomic exchange. The in-memory store
  has rollback/fault injection, one-winner contention, digest and authorization
  ID collision checks, binding/expiry/account/client coverage, secret-safety
  properties, and public durable-adapter conformance. Lost post-commit token
  responses are deliberately not replayed because raw tokens are never stored.

## P2: Dart developer experience and platform integration

- [ ] Complete typed persistence adapters for the supported Routed storage
  paths. `routed_auth_cloudflare` now supplies a typed, migrated D1 `AuthStore`
  and a backend-owned deletion coordinator that pass local conformance,
  rollback, contention, and fault tests. It now owns OAuth provider-mode
  code/token exchange, managed SCIM connections, username mutations, the typed
  anonymous create/delete/upgrade contract, bounded digest-only API keys
  through append-only migration version 9, and bounded digest-only WebAuthn
  challenges plus passkeys through version 10. It now also owns bounded
  digest-only phone issuance, verification, identity binding, projection, hard
  deletion, and authentication-method inventory through migration version 11.
  A disposable live-D1 run passed
  all 41 cases enabled through migration v7, including the anonymous cases,
  and its owned database was independently confirmed deleted. The API-key v9
  WebAuthn v10, and phone v11 cases are wired into the opt-in harness but have
  not run against live D1. Broader SQL adapters and future-plugin plans remain
  open. D1's authentication-method coordinator accepts its own users,
  credentials, accounts, email-OTP, exact phone, exact API-key, and exact
  passkey stores;
  external method stores require a future backend-bound plan. Mixed topologies
  remain usable but account unlink fails closed. Removed external plugins are
  not discoverable automatically:
  durable adapters must retain a historical namespace inventory or reject
  deletion until that namespace has backend-owned cleanup.
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
- [x] Make device-token issuance crash/retry-safe with bounded digest-only
  leases, a typed authorization-ID-idempotent application issuer, guarded
  in-memory and D1 completion/release transitions, and an explicit
  at-most-once response-delivery boundary without persisted token material.
- [x] Add OpenAPI 3.1 endpoint and model generation for core auth routes and
  composed plugin routes, with generated-client compatibility tests.
- [x] Publish framework-neutral store and runtime conformance APIs for durable
  adapters and IO, Node, and Fetch hosts.
- [x] Add reusable provider fixtures and end-to-end helpers for credentials,
  email/phone OTP, OAuth/OIDC, WebAuthn, API keys, and two-factor flows beyond
  the shared runtime conformance contract.
- [x] Update the package READMEs and examples only after the public APIs and
  security defaults settle.

## Longer-term plugin-inspired backlog

These capabilities are useful product benchmarks, but should follow the core
account, session, client, and plugin contracts above:

- [x] Add email OTP as a separate one-time-code flow alongside magic links.
- [x] Move magic-link and email-OTP issuance, attempt accounting, one-time
  consumption, and user transitions behind required typed backend commands;
  persist only digests, publish durable-adapter conformance, and keep delivery
  plus host session/cookie issuance as explicit postcommit boundaries.
- [x] Add phone-number authentication with provider-owned delivery and a
  required root `AuthPhoneNumberBackend`. Digest-only issuance, bounded
  attempts/lockout, expiry, one-time verification, user/phone binding,
  sign-up projection, rollback, replay, contention, and hard deletion are one
  typed backend transaction contract with public adapter conformance and
  hostile state-sequence properties. SMS, callbacks, and host session/cookie
  issuance remain explicit postcommit boundaries. D1 fails closed until it
  implements these commands.
- [x] Add username-first authentication and explicit identifier policy.
  Registration, rename, and safe removal reserve normalized identifiers through
  a root store-owned atomic capability, with public adapter conformance,
  contention, rollback, replay, and hostile-input coverage.
- [x] Add anonymous/guest sessions with safe account upgrade/linking rules.
- [x] Track the last successful authentication method through independent
  server/client plugins without storing identities, credentials, or secrets.
- [x] Add captcha and breached-password checks as opt-in security plugins.
- [x] Add a bounded SCIM 2.0 server plugin with application-owned token and
  atomic provisioning boundaries, immutable connection/tenant/organization/
  provisioning-domain isolation, strict User CRUD/patch/filter/page contracts,
  explicit inactive/tombstoned lifecycle, generic errors, and OpenAPI metadata.
  Keep directory truth separate from auth users and keep SCIM server-only.
- [x] Add connection-owned SCIM Groups and direct User/Group membership
  resources with bounded equality filters/pages/members, exact Group scopes,
  atomic store mutation boundaries, tombstones, generic errors, Routed/OpenAPI
  transport, and a stable-resource-ID-only application role/membership
  projection capability. Keep the real projection transaction application-owned.
- [x] Add explicit application-owned identity projection and complete-snapshot
  reconciliation around exact connection-bound SCIM resource IDs, with
  optimistic/idempotent commands, drift detection, final tombstones, validated
  Group references, rollback conformance, and permanent scope-deletion fences.
  Never infer links from email or grant sign-in access from provisioning alone.
- [x] Add a managed connection and digest-only credential catalog with scoped,
  expiry/revocation-aware one-time issuance and rotation APIs, required
  idempotency payload binding, exact tenant/organization authorization,
  bounded catalogs, atomic disable/deletion cleanup, adapter conformance,
  Routed/OpenAPI contracts, and an independently selected client plugin.
- [x] Add the first SAML SSO server/client plugin slice with immutable typed
  connections, exact provider/IdP/NameID identity, SP metadata, HTTP-POST
  AuthnRequest and ACS flows, durable atomic request/assertion replay state,
  strict XML bounds and assertion validation, host-owned session issuance,
  OpenAPI contracts, and an application-owned XMLDSig verifier seam.
- [x] Add a built-in portable XMLDSig verifier after exact reference binding,
  bounded exclusive canonicalization/transforms, pinned certificates, explicit
  RSA/SHA-2 allowlists, independent xmlsec fixtures, hostile XML vectors, and
  generated mutations pass the public verifier conformance suite.
- [ ] Prove live SAML interoperability against external IdPs. Dynamic SSO
  administration, OIDC enterprise connections, encrypted assertions, logout,
  and group/role mapping remain deferred.

## Active security-audit remediation

- [x] Route every plugin-authenticated identity through host-owned session
  issuance. WebAuthn JWT authentication must not report success without a
  usable session, and phone, anonymous, email-OTP, username, and WebAuthn must
  all honor the configured JWT body-token policy, callbacks, and events.
- [x] Require browser-origin protection for anonymous and email-OTP sign-in
  while retaining explicit native-client behavior.
- [x] Derive bounded, non-secret rate-limit identifiers from typed plugin
  requests, use each operation namespace as provider identity, and preserve
  that metadata through the Routed rate-limit adapter.
- [x] Prevent public WebAuthn authentication options from revealing enrollment
  or credential IDs, and validate presented certificate chains against
  out-of-band trust anchors when the root is omitted from `x5c`.
- [x] Start captcha replay retention after successful provider verification so
  slow providers cannot make an accepted token immediately reusable.
- [x] Make plugin conformance consume actual installed client operation and
  codec contracts instead of comparing only server-declared descriptors.
- [x] Constrain Routed auth deployment binding to `EngineContext` and reject an
  incompatible context at startup instead of silently omitting auth routes.
- [x] Replace callback-based hard deletion with immutable backend-bound plans
  executed with core deletion by one storage coordinator. The in-memory
  topology covers Admin, anonymous, email OTP, API keys, WebAuthn, two-factor,
  organizations, device authorization, phone number, and OAuth provider mode;
  incomplete, duplicate, unsupported, and foreign-domain plans fail before
  mutation, with reusable rollback, contention, and fault tests. D1 supplies
  native device-authorization, email-OTP, and API-key plans, owns anonymous
  mutation and receipt cleanup inside its core transaction, always cleans those
  backend-owned tables, and fails closed for active external plugins without a
  D1 plan.
- [x] Make organization last-owner checks transactional across removal,
  demotion, role replacement, leave, and user-deletion paths, with reusable
  durable-store conformance and contention coverage.
- [x] Move invitation, role, team, and team-member writes behind typed atomic
  store commands that recheck scoped actor/target snapshots; enforce capacity,
  uniqueness, cascades, and creator preservation under contention; and persist
  exact-bound idempotency results for retried create/invite/add operations.
  Adapter conformance covers deterministic replay, conflicts, rollback, and
  concurrent capacity. Store-confirmed retries skip delivery and post-commit
  callbacks; pre-commit transformation hooks remain an honest repeatable host
  boundary outside the store transaction.
- [x] Retain a one-way user-ID digest receipt so explicit user-ID reuse cannot
  reactivate credentials or JWTs after hard deletion. In-memory and D1 receipt
  writes participate in the same rollback boundary as core deletion.

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
  and native `routed_node`, and native Cloudflare Fetch request paths. The
  provider-free plugin matrix also covers typed magic-link client/server
  composition, provider-path placeholder binding, browser-bound one-time
  callbacks, hostile-token sanitization, concurrent replay, and typed
  phone-number client/server composition. The phone flow covers provider-owned
  delivery, exact send/verify paths, browser-origin and CSRF policy,
  cookie-backed sessions, hostile phones/codes, generic delivery failures,
  bounded attempt lockout, sequential replay, and eight-way verification with
  exactly one winner. Email OTP, username, API-key exchange, successful
  browser-shaped WebAuthn registration and DER-signed authentication,
  challenge/counter replay, sanitized WebAuthn errors, anonymous auth, and
  two-factor route gating also run on each applicable host.
  Deterministic OAuth/OIDC and custom callback
  providers now cover state, PKCE, nonce, browser binding, replay, account
  linking, redirect safety, provider failures, and host-owned session/JWT
  issuance across IO, portable/native Node, and portable/native Cloudflare
  Fetch adapters.
- [x] Run the D1 conformance harness against a deployed or remote-bound
  Cloudflare database. On 2026-08-20, all 41 cases enabled through anonymous
  migration v7 passed against a disposable remote D1 database. The ownership
  guard deleted the database, and a separate account listing confirmed that no
  disposable `routed-auth-conformance` database remained. The API-key v9,
  WebAuthn v10, and phone v11 non-fault cases are wired into the opt-in
  harness but have not been run live.
- [x] Keep the current auth packages, host adapter integrations, and public
  conformance suites analyzer-clean and passing on `master`.

## Definition of done

- [x] Audit every production path to ensure plaintext passwords are neither
  persisted nor compared directly. Built-in registration, sign-in, reset,
  change, administration, email-change, and deletion paths all use the
  configured password hasher.
- [x] Every advertised portable and host-owned auth endpoint explicitly
  declares read-only or mutation semantics. Mutations carry typed persistence,
  atomicity, and replay behavior; conformance validates plugin schema and
  atomic-operation references, and OpenAPI preserves the public contract.
  The audit intentionally records weaker guarantees where implementations are
  multi-step: OAuth's mixed-grant token endpoint cannot atomically combine
  authorization-code consumption with token issuance; device token polling,
  claiming, and application token delivery are separate steps; WebAuthn
  verification consumes a challenge separately from authenticator creation or
  counter updates; Admin ban/disable can require separately persisted plugin
  revocation; Admin impersonation replacement sessions are host-owned; and
  organization update plus its host callbacks spans store or host boundaries
  without one declared transaction. Two-factor durable mutations now resolve
  to the required backend-owned atomic command schema. Pending challenge
  completion deliberately remains a host-session operation because session and
  cookie delivery occurs after the durable command commits. Password
  change/reset and trusted-device revocation also remain separate host and
  plugin transactions. Username registration, rename, and safe removal now
  publish atomic persistence descriptors backed by the root
  `AuthUsernameStore` transaction capability. The remaining weaker operations
  stay
  `nonAtomic` or `unguarded` until their adapters expose a stronger bounded
  operation.
- [x] Every advertised auth endpoint has documented authentication,
  CSRF/origin, rate-limit, redirect, session/body-token, and error semantics in
  the public auth endpoint security contract, including plugin-gated 2FA route
  mounting.
- [x] The shared credentials/session runtime contract is verified through
  `routed_io`, native Node, and native Cloudflare Fetch request paths.
- [ ] Every advertised plugin flow has matching end-to-end coverage across its
  applicable host runtimes. Provider-free flows now run across IO, Node, and
  Cloudflare Fetch, and deterministic external-provider callbacks run across
  IO, portable/native Node, and portable/native Cloudflare Fetch, including
  successful browser-shaped WebAuthn ceremonies. Typed phone-number auth now
  has the same IO, portable/native Node, and portable/native Cloudflare Fetch
  coverage, including delivery, browser/session boundaries, lockout, secrecy,
  and one-winner consumption. An opt-in, token-protected deployed Worker
  harness now compiles and runs every suite without invoking Cloudflare
  control-plane APIs; an authorized run against an actual deployed Worker
  remains.
- [x] Security-sensitive defaults are safe without requiring users to discover
  undocumented configuration switches. Durable options fail closed as
  production posture and require an exact HTTPS origin/proxy boundary, secure
  browser and cookie policy, production account defaults, an explicit rate
  limiter, and algorithm-sized JWT secrets; ephemeral local development is an
  explicit typed posture.
