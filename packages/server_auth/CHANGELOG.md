## Unreleased

- Complete public Dartdoc for authentication-method, JWT, and rate-limit APIs.
- Complete public Dartdoc for the client, plugin, provider, and store contracts.
- Complete public Dartdoc for admin, organization, account-lifecycle, and
  anonymous-user APIs.
- Complete public Dartdoc for the SAML and SCIM integration APIs.
- Add the `reauthentication` rate-limit action and typed client method for
  refreshing a current session's sensitive-action proof.
- Mirror only the short-lived OAuth state into the framework session when a
  durable challenge store is configured, so adapters can validate the browser
  binding even if the separate state cookie is not returned by a host. Remove
  the mirrored state as soon as the durable challenge is consumed.
- Fix GitHub OAuth sign-in against the current GitHub REST API by sending the
  required `User-Agent`, media-type, and API-version headers when loading the
  authenticated user profile. Keep the bounded JSON parsing and private-email
  fallback in the provider-specific request path.
- Add regression coverage that verifies GitHub user-info requests include the
  required headers before profile mapping is attempted.
- Add typed framework-session lifecycle hooks to `AuthOptions`, allowing
  adapters to synchronize host-owned session cookies after auth sign-out
  without coupling the auth core to a specific HTTP framework.
- Add compact framework-session principal projection so provider profile
  metadata cannot overflow browser-backed session cookies during sign-in.
- Bound the direct email, display-name, and avatar claims included in compact
  framework-session principals by UTF-8 byte size, not only provider-profile
  fallback attributes, so multibyte values cannot overflow browser cookies.

## 0.2.0 - 2026-08-20

- Breaking: require every `AuthServerPlugin` to publish an
  `AuthServerPluginDataContract`. The registry now verifies that plugin-owned
  authentication-method and user-data namespaces match their typed inventory
  and deletion contributors, and that declared credential-removal or rotation
  routes are recent-authenticated mutations owned by the plugin.
- Add typed historical authentication-method namespaces to `AuthOptions` and
  the shared inventory service. Removed future-plugin namespaces now make
  destructive in-memory mutations fail closed until their contributors return.
- Add typed historical user-data namespaces to `AuthOptions` and the deletion
  coordinator capability. Removed plugin data now makes hard deletion fail
  closed until its contributor returns.
- Add typed recent-authentication endpoint metadata and require it for
  username, phone, passkey, and API-key credential-removal mutations. Routed
  enforces the metadata with the configured recent-auth or step-up policy.
- Add the protected JWT `auth_time` claim and preserve it across automatic
  refreshes and application claim callbacks. Sensitive-action policy now uses
  the original authentication time instead of refreshable JWT `iat`; legacy
  tokens fall back to their original `iat` until first refresh.
- Breaking: replace callback-style SCIM identity, lifecycle, and role
  projection seams with `AuthScimApplicationProjectionStore`. Projection keys
  now contain only the exact connection/tenant/organization/provisioning-domain
  binding, SCIM resource ID, and resource kind; email and auth-user lookup are
  not representable in the contract.
- Add typed optimistic/idempotent projection commands, complete-snapshot drift
  detection and reconciliation, final resource tombstones, validated stable-ID
  group membership, and snapshot-checked connection-scope deletion fences.
- Add a transactional in-memory reference store plus reusable durable-adapter
  conformance and generated property coverage for rollback, contention,
  operation rebinding, scope isolation, hostile identifiers, deletion races,
  and the invariant that projection cannot create a sign-in identity.
- Add an optional backend-owned WebAuthn deletion-plan capability and exact
  passkey-removal transaction. Mixed durable stores fail closed, while base
  `AuthStore` implementations remain source-compatible without WebAuthn.
- Export reusable WebAuthn challenge, credential-uniqueness, counter-CAS,
  contention, lifecycle, and passkey-removal conformance/property coverage.
- Add the exact `AuthApiKeyPrimaryMutationStore` command for durable safe
  primary-key revocation. Adapters recheck supported fallbacks inside their own
  transaction; unsupported and mixed stores fail closed without invoking the
  old process-local callback path.
- Export `AuthApiKeyStoreConformanceSuite` for reusable lifecycle, capacity,
  contention, single-use rotation, ownership, expiry, and rollback validation.
- Breaking: replace the phone plugin's split challenge/user/identity stores
  with a required root `AuthPhoneNumberBackend`. Digest-only issuance,
  bounded attempts and lockout, expiry, one-time consumption, sign-up,
  verified-user projection, unique phone ownership, and deletion cleanup are
  now backend-owned atomic commands with no fallback bridge.
- Add in-memory rollback/fault injection, replay and contention coverage,
  hostile property-based phone/code/state sequences, and a public durable
  adapter conformance suite. SMS delivery, verification callbacks, and host
  session/cookie issuance are documented postcommit boundaries.
- Serialize in-memory phone commands with coordinated hard deletion so a
  deletion rollback cannot overwrite a concurrently committed issuance or
  verification mutation.
- Add the typed `AuthPhoneNumberMutationStore` capability for safe verified
  phone removal. The phone plugin now clears its identity, verification state,
  and verified-user projection only when another usable authentication method
  remains; hosts still own recent-auth or step-up authorization.
- Breaking: move anonymous creation, authenticated deletion, and account-
  upgrade finalization behind `AuthAnonymousAccountMutationStore`. Remove the
  arbitrary link callback; durable adapters now fail configuration unless they
  provide backend transactions and replay receipts, while session issuance
  remains host-owned.
- Add atomic in-memory anonymous mutations, rollback fault injection, public
  durable-adapter conformance, and property coverage for contention, replay,
  deletion rollback, operation binding, generated-name bounds, control
  characters, and privilege-bearing anonymous records.
- Breaking: replace endpoint and client path strings with canonical
  `AuthRoutePath` contracts, typed `{parameter}` keys, and explicit
  `AuthEndpointMount.auth`/`root` placement. Requests now expose isolated path,
  query, and body namespaces; client resolution requires an exact parameter
  set and safely encodes each segment.
- Bind managed SCIM authorization principals to the authenticated session user
  so credential ownership and coordinated deletion cannot be assigned to a
  different account by a faulty application authorizer.
- Replace independent Admin store writes with typed backend-owned mutation
  commands that revalidate exact custom-role permissions inside the
  transaction, serialize competing user changes, and roll credentials,
  sessions, JWT versions, and admin state back on failure. Make impersonation
  session transitions single-use, preserve the existing deletion coordinator,
  and add public durable-adapter conformance plus stateful/property coverage.
- Breaking: require `TwoFactorPlugin` to use one `AuthTwoFactorBackend` with
  typed backend-owned atomic commands. Remove the pending-recovery coordinator
  and all fallback orchestration; enrollment verification, bounded attempts,
  recovery use/regeneration, pending completion, disablement, trusted devices,
  and step-up proofs now share the declared command boundary.
- Add `InMemoryAuthTwoFactorBackend` per-user serialization, rollback and fault
  injection, schema-backed atomic operation metadata, and public durable
  adapter conformance through `package:server_auth/testing.dart`. Host session
  and cookie delivery remains explicitly outside pending-challenge commands;
  host password mutations remain outside trusted-device revocation commands.
- Add a separate plugin-first managed SCIM connection API with exact tenant,
  organization, subject, provisioning-domain, and scope binding; atomic
  connection/initial-credential creation, updates, disablement, rotation,
  revocation, subject/tenant deletion, bounded catalogs, and expiry handling.
  Credentials persist only a strong digest and safe metadata; first delivery
  is one-time, while idempotent replays return metadata without reconstructing
  the raw secret. Add a separately selected typed client and reusable adapter
  conformance plus fault, contention, and property coverage.
- Replace username credential sub-store mutation with the required root
  `AuthUsernameStore` capability. Registration, normalized rename, and safe
  removal are now store-owned atomic operations with generic public failures,
  deterministic replay behavior, fail-closed topology checks, public durable
  adapter conformance, fault injection, contention, and hostile-identifier
  property coverage. This is a breaking adapter API with no compatibility
  bridge.
- Replace the legacy magic-link provider with opt-in `MagicLinkPlugin` server
  composition and require typed `AuthMagicLinkBackend` and
  `AuthEmailOtpBackend` commands for one-time email state transitions. Persist
  only SHA-256 magic-link digests and keyed, domain-separated OTP digests;
  include hostile-input/state-machine properties, exactly-one-winner replay
  conformance, rollback tests, and explicit postcommit delivery/session limits.
- Replace pre-issuance device-grant consumption with bounded digest-only
  issuance leases and a typed authorization-ID-idempotent application token
  issuer. Matching completion/release transitions make ambiguous failures and
  process crashes retry-safe without storing access or refresh tokens; the
  post-completion HTTP response remains an explicit at-most-once delivery
  boundary. Rename the corresponding public store-conformance case from
  `device-authorization.approve-claim-contention` to
  `device-authorization.approve-lease-contention`.
- Extend the opt-in SCIM server plugin with typed, connection-owned Groups,
  bounded equality filters and pagination, direct User/Group member references,
  atomic create/replace/patch/membership/tombstone store boundaries, exact Group
  scopes, stable-ID-only application role projection, generic failures, and
  stateful/property coverage for isolation, bounds, conflicts, and replay.
- Move high-risk organization invitation, membership, role, team, and
  team-member writes behind typed snapshot-checked store transactions with
  rollback, contention conformance, and exact-bound idempotent replay for
  create/invite/add operations.
- Require bounded caller idempotency keys in typed organization clients and
  document lifecycle hooks, delivery, audit, and event sinks as post-commit
  host boundaries.
- Add optional typed SAML server/client plugins with immutable application-owned
  connections, signed NameID identity resolution, SP metadata, HTTP-POST
  AuthnRequest/ACS flows, browser-bound one-time RelayState, durable atomic
  request/assertion replay contracts, bounded hostile XML handling, strict
  assertion validation, and host-owned session issuance.
- Require an application-owned `AuthSamlAssertionVerifier` until portable
  XMLDSig reference binding is proven, and publish a verifier conformance
  runner instead of presenting synthetic test signatures as production SAML.
- Add `AuthPortableSamlXmlDsigVerifier` behind that seam with exact direct-
  parent reference binding, pinned single-certificate trust, bounded exclusive
  canonicalization and transforms, explicit RSA/SHA-2 allowlists, independent
  xmlsec fixtures, hostile XML vectors, and property-based mutation coverage.
- Replace split authorization-code consumption and access-token persistence
  with a required typed exchange store owned by `OAuthProviderModePlugin`.
  Code bindings are revalidated and consumed with the digest-only prepared
  token record in one adapter transaction; in-memory rollback, contention,
  collision, expiry, wrong-binding, disabled-account/client, and property
  coverage are included.
- Add public durable-adapter conformance for authorization-code exchange and
  declare atomic single-use token-endpoint semantics only for code-only grant
  configurations. A lost post-commit HTTP response remains intentionally
  non-replayable because raw token values are never persisted.
- Require durable OAuth client and authorization-code exchange stores to
  identify one backend-owned persistence domain. Durable provider mode now
  rejects split or in-memory topologies instead of falling back.
- Require every portable and host-owned endpoint to publish typed read or
  mutation semantics, including persistence boundary, atomicity, replay
  behavior, and validated persistence-schema/atomic-operation references.
- Extend plugin conformance with negative mutation-contract fixtures and audit
  built-in endpoint metadata without overstating multi-step transaction or
  replay guarantees.
- Make auth runtime posture fail closed: durable options now require an exact
  HTTPS origin/proxy boundary, secure browser and cookie policy, production
  account defaults, an explicit rate limiter, and algorithm-sized JWT secrets,
  while ephemeral local development selects coherent development defaults
  explicitly.
- Revalidate production posture in `AuthRuntime` and keep deployment proxy
  policy identical to the boundary carried by `AuthOptions`.
- Add an opt-in HTTPS FIDO MDS 3.1.1 downloader with bounded same-origin
  redirects, response limits, one per-hop connect/headers/body deadline, one
  non-resetting total refresh deadline, conditional refreshes, source-bound
  fresh 304 reuse, and monotonic blob enforcement. Add built-in ES256/RS256 JWS
  verification over exact pinned RFC 5280 paths with strict certificate
  constraints and fail-closed application-owned revocation for every non-anchor
  certificate.
- Add an opt-in, server-only SCIM 2.0 plugin with application-owned bearer
  resolution and atomic provisioning persistence, immutable connection/tenant/
  organization/provisioning-domain isolation, digest-only scoped credential
  contracts, strict typed discovery and User schemas, bounded equality
  filters/pagination/patches, explicit directory lifecycle and tombstones, and
  generic protocol errors. SCIM Users remain separate from auth users and
  application access; no SCIM client plugin is installed implicitly.
- Extend portable plugin contracts with PUT, PATCH, DELETE, plugin-owned bearer
  authentication, explicit HTTP status/media-type responses, path parameters,
  and conformance validation for duplicate or malformed response contracts.
- Add a typed, plugin-composed authentication-method inventory spanning
  credentials, exact OAuth accounts, passkeys, phone, email OTP/link,
  usernames, opt-in primary API keys, and future plugin methods. Breaking:
  destructive method removal now uses one backend-bound atomic coordinator,
  fails closed for incomplete/non-transactional stores, and has no legacy
  safe-unlink adapter path.
- Add an explicit sensitive-action policy for account unlinking. A verified
  password, a valid step-up proof, or a session/JWT issued inside the configured
  recent-authentication window can authorize passwordless unlinking.
- Allow `WebAuthnPlugin` to use explicit typed WebAuthn storage when the root
  auth store does not own passkey tables. Mixed-backend runtimes remain usable,
  while destructive method removal fails closed unless the root coordinator can
  transact every active inventory.
- Replace callback-based hard deletion with immutable, backend-bound plugin
  plans executed alongside core deletion by one storage coordinator. Freeze
  the deletion topology, reject incomplete or foreign-domain plans before
  mutation, clean backend-owned optional substores even after their plugin is
  removed, retain a user-ID digest receipt against credential reactivation,
  and add reusable rollback, contention, and fault conformance.
- Reject ASCII control characters in callback redirects before URI parsing so
  header-injection payloads cannot reach host response adapters.
- Add deterministic browser-shaped WebAuthn test ceremonies with real ES256
  keys, `none` attestation, and ASN.1 DER assertion signatures for offline host
  conformance suites.
- Extend the public plugin conformance suite with executable installed-client
  contracts that verify real method/path/request behavior, server request-codec
  and response-schema alignment, response decoding, optional topology,
  malformed responses,
  duplicate IDs, and secret-safe public results across independent plugins.
- Add offline FIDO Metadata Service 3.1.1 blob parsing and WebAuthn trust
  evaluation with bounded inputs, monotonic update checks, optional freshness
  enforcement, typed provenance, and an explicit application-owned JWS/PKIX
  verification boundary.
- Add an opt-in last-authentication-method server/client plugin with a bounded
  allowlist, HMAC-protected expiring browser state, and lifecycle hooks that
  update only after successful host session issuance and clear on sign-out or
  account deletion.
- Add opt-in phone-number authentication with strict E.164 identifiers,
  digest-at-rest one-time codes, bounded replay attempts, provider-owned
  delivery, session issuance, lifecycle deletion, and a typed client plugin.
- Add opt-in username authentication with an explicit typed identifier policy,
  atomic normalized-identifier ownership, generic public failures, session and
  two-factor integration, and a separately selected typed client plugin.
- Add opt-in captcha and breached-password policy plugins with bounded,
  fail-closed application provider contracts, generic public failures,
  property coverage, and a captcha-aware credentials client plugin.
- Add an explicit WebAuthn attestation trust policy with
  accept/reject/downgrade decisions and exact local trust roots, plus strict
  Ed25519 registration, packed self-attestation, and assertion verification.
- Add strict Android Key, Apple Anonymous, and TPM 2.0 WebAuthn attestation
  verification with browser-shaped fixtures, certificate-chain validation,
  public-key binding, and fail-closed malformed-input handling.
- Include pending two-factor recovery challenges in plugin-owned deletion
  plans so account removal cannot leave reusable recovery state behind.
- Require browser-origin validation for anonymous and email-OTP sign-in, and
  begin captcha replay retention only after provider verification succeeds.
- Make public WebAuthn authentication options enrollment-indistinguishable and
  validate certificate paths against configured trust anchors even when the
  authenticator omits the root from `x5c`.
- Preserve an organization owner through atomic, snapshot-checked membership
  removal, leave, demotion, role replacement, role mutation, and user-deletion
  operations, with a public durable-store ownership conformance helper.
- Publish deterministic testing fixtures for credentials, email and phone OTP,
  OAuth/OIDC, WebAuthn payloads, API keys, and two-factor flows, plus portable
  endpoint-codec, HTTP, clock, delivery, gate, and concurrency helpers.
- Replace plugin-side session issuance with a typed authentication intent so
  hosts uniformly enforce account policy, callbacks, session/JWT strategy,
  token projection, and lifecycle events after successful plugin verification.
- Require a keyed email-OTP rate-limit secret and derive bounded HMAC target
  identifiers without exposing canonical emails or OTPs; require CSRF for
  authenticated anonymous-account deletion.
- Extend the public durable-store conformance suite with contention cases for
  users, credentials, accounts, sessions, tokens, OAuth challenges, JWT
  versions, device authorization, and email OTP.
- Consolidate application-hosted OAuth 2.0 and OpenID Connect on
  `OAuthProviderModePlugin`, with digest-at-rest one-time authorization codes,
  PKCE, grants, refresh, introspection, userinfo, discovery, asymmetric ID-token
  signing, and JWKS.
- Add RFC 8628 device-token polling with server intervals, `Retry-After`,
  `slow_down` backoff, deadlines, and caller cancellation.
- Add typed local-development, secure-session, JWT API, and service API-key
  deployment presets with explicit production store, origin, proxy, delivery,
  rate-limit, and verified-email decisions.
- Publish `package:server_auth/testing.dart` with a framework-neutral
  `AuthStoreConformanceSuite` for durable adapter implementations.
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

- Add the opt-in typed `WebAuthnPlugin` with digest-at-rest one-time challenges,
  durable authenticator/counter contracts, `none`, packed self/certificate, and
  FIDO U2F, Android Key, Apple Anonymous, and TPM 2.0 attestation, browser DER
  ES256 assertions, ES256/RS256 packed verification, exact origin/RP-ID binding,
  and replay-safe counters. FIDO metadata and deprecated attestation formats
  remain explicit follow-up work.
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
