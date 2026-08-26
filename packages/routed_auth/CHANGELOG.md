# Changelog

## 0.2.1 - 2026-08-25

- Adopt `very_good_analysis` with strict typing, complete public API
  documentation, and package-safe imports across the library, examples, and
  tests.
- Keep auth lifecycle events from retaining raw request contexts; publish only
  bounded, non-secret request metadata and add regression coverage for request
  secret isolation.
- Complete public docs for routed API-key, browser-protection, deployment,
  JWT, OAuth, provider, and last-authentication-method adapters.
- Complete public Dartdoc for the crypto, route, gate, and conformance APIs.
- Add a session-bound password reauthentication endpoint and manager API for
  refreshing sensitive-action proofs without replacing the current session.
  Reauthentication is rate-limited, supported for session and JWT strategies,
  and exposed through the typed auth client.
- Fall back to the encrypted framework session for the browser-bound OAuth
  state when a host drops the auxiliary state cookie during a cross-site
  redirect. The durable OAuth challenge and one-time consumption rules remain
  unchanged, with regression coverage for the missing-cookie path.
- Consolidate authentication sign-out through `AuthManager.signOut`, which
  revokes the auth session, propagates the signed-out lifecycle event to
  configured plugins, and publishes the Routed sign-out event. Applications
  can explicitly request framework-session destruction when the auth cookie
  owns the complete application session. Add framework-session hooks so
  adapters can expire host-owned cookies from the manager rather than from
  individual routes.
- Store a compact principal for automatic sign-in so large OAuth provider
  profiles cannot exceed browser session-cookie limits. Add a regression test
  covering a large GitHub profile and the subsequent authenticated request.

## 0.2.0 - 2026-08-20

- Add a pinned Keycloak interoperability harness for real signed SAML
  responses. It starts an isolated HTTPS IdP, exercises the typed provider
  path and ACS/session boundary, verifies the browser form flow, and removes
  the container and temporary certificates on exit.
- Enforce host-owned recent-authentication or step-up proof before sensitive
  plugin mutations, including phone and username removal, passkey deletion,
  and API-key revoke/rotate operations. Add the phone removal route and typed
  client method.
- Authorize passwordless linked-account removal from the protected JWT
  `auth_time` claim, not the automatically refreshed `iat`. Token refresh and
  JWT callbacks cannot silently renew the recent-authentication window.
- Mount phone issue/verification operations only when the root auth store
  provides `AuthPhoneNumberBackend`, preserving atomic digest-only challenge,
  attempt/lockout, one-time consumption, user creation/projection, and phone
  binding semantics. Routed session/cookie issuance remains postcommit, and
  durable stores without the commands fail closed instead of using a side
  in-memory store.
- Re-export the server-neutral typed SCIM application projection and
  reconciliation API. It intentionally contributes no Routed route, session,
  authentication method, or client plugin; application code coordinates it
  through its own transaction or durable outbox.
- Finalize anonymous-account upgrades through the plugin's typed backend
  transaction only after Routed has issued the authenticated target session.
  Remove callback-based migration orchestration and keep failed session
  issuance from deleting the anonymous source.
- Mount portable auth endpoints from their typed route and explicit mount
  contracts, preserve path/query/body namespaces through dispatch, and forward
  only the allowlisted Authorization header to portable handlers.
- Route Admin mutations through backend-owned typed commands, consume
  impersonation source sessions once before host replacement-session creation,
  and preserve the explicit host-session and post-commit audit boundary.
- Route all opt-in two-factor mutations through the plugin's required typed
  atomic backend, including pending TOTP/recovery completion, trusted devices,
  disablement, recovery regeneration/use, and session-bound step-up proofs.
  Routed still issues sessions and delivers cookies after the command commits,
  so failed host delivery requires a fresh sign-in challenge. Password
  mutation and trusted-device revocation also remain separate backend commands.
- Mount the opt-in managed SCIM connection and credential catalog with shared
  session, browser-origin, CSRF, rate-limit, and generic-error enforcement;
  preserve one-time raw-secret delivery and exact application-authorized
  tenant/organization binding across create, list, update, disable, issue,
  rotate, revoke, and bounded catalog operations.
- Mount the opt-in username plugin's authenticated, CSRF-protected rename and
  safe-removal operations, preserving generic failures, idempotent replay,
  store-owned atomicity metadata, and the separately selected typed username
  client surface.
- Compose magic-link authentication through `MagicLinkPlugin`, resolve plugin
  providers through the runtime, reject hostile one-time email identifiers as
  public auth errors, and preserve browser binding while durable consumption
  commits before non-replayable host session/JWT and cookie issuance.
- Route device-token polling through the bounded issuance-lease protocol so
  issuer failures can retry with the same stable authorization ID while
  concurrent, stale, disabled-account, and consumed grants fail generically.
- Mount the opt-in SCIM Groups collection and resource operations across
  GET, POST, PUT, PATCH, and DELETE while preserving Group scopes, SCIM media
  types/status codes, and host-owned session isolation.
- Require bounded idempotency keys on Routed organization create/invite/add
  routes and preserve the server plugin's atomic snapshot, capacity, cascade,
  and deterministic replay contract through portable endpoint metadata.
- Mount opt-in SAML metadata, sign-in, and form-encoded ACS routes, preserve
  dynamic provider path parameters, emit protocol content types, and complete
  verified identities through Routed's host-owned session/JWT and redirect
  boundary.
- Derive Routed auth runtime durability from typed `AuthOptions` posture,
  removing the independently configurable provider durability flag, and
  require production options to boot through one typed deployment so proxy,
  browser, cookie, and store guarantees cannot drift apart.
- Mount the opt-in SCIM 2.0 server plugin across GET, POST, PUT, PATCH, and
  DELETE while forwarding its bearer credential only to the application-owned
  atomic connection resolver,
  preserving SCIM media types/status codes, and never creating a user session.
- Make linked-account unlinking password-optional when the request has a valid
  two-factor step-up proof or a sufficiently recent original server-session or
  JWT issue time. Exact provider/account targets are removed through the shared
  atomic authentication-method coordinator; stale authentication is rejected
  and stores without that transaction capability fail closed.
- Add a public deterministic external-provider runtime conformance fixture for
  OAuth/OIDC and custom callback providers, covering state, PKCE, nonce,
  browser binding, replay, account linking, redirect safety, bounded failures,
  and host-owned session/JWT issuance across IO, Node, and Cloudflare Fetch.
- Publish a framework-neutral plugin runtime conformance fixture covering
  typed magic-link client/server composition, browser-bound one-time callbacks,
  hostile-token sanitization, concurrent replay, email OTP, username, API-key
  exchange, successful browser-shaped WebAuthn registration and DER-signed
  authentication, challenge/counter replay, WebAuthn error boundaries,
  anonymous auth, and two-factor route gating across IO, Node, and Cloudflare
  Fetch hosts.
- Extend the shared host fixture with independently installed phone-number
  server and typed client plugins. IO, portable/native Node, and
  portable/native Cloudflare Fetch now exercise provider-owned delivery,
  exact send/verify paths, origin and CSRF policy, cookie-backed sessions,
  bounded hostile input, generic provider failures, attempt lockout,
  sequential replay, and concurrent verification with exactly one winner.
- Add the Routed browser adapter for the opt-in last-authentication-method
  plugin, using a Secure, HttpOnly, SameSite cookie and host-owned successful
  authentication/sign-out/account-deletion lifecycle events.
- Mount phone-number send/verify operations from the opt-in server plugin and
  issue normal Routed sessions after successful verification.
- Mount opt-in username registration and sign-in operations with typed
  identifier policy, normal session/two-factor handling, and an independently
  selected username client plugin.
- Apply opt-in captcha checks to credential sign-in/registration and
  breached-password checks to registration, reset, and password change while
  preserving generic HTTP failures and existing rate limits.
- Add `RoutedAuthDeploymentBinding` helpers to bind typed auth options, create
  the matching service provider, and apply explicit proxy policy to the Routed
  engine configuration.
- Restrict Routed deployment helpers to `EngineContext`, reject substituted or
  missing auth option bindings at startup, and cover invalid contexts with a
  compile-failure fixture.
- Enforce trusted browser origins for anonymous and email-OTP sign-in while
  preserving explicit native-client requests.
- Centralize successful phone, anonymous, email-OTP, username, WebAuthn, and
  admin-impersonation session issuance in Routed, including JWT cookies,
  configured body-token exposure, callbacks, policy, and lifecycle events.
- Mount two-factor routes only when `TwoFactorPlugin` is selected, enforce CSRF
  for anonymous-account deletion, and preserve keyed email-OTP limiter IDs.
- Publish `package:routed_auth/testing.dart` with a framework-neutral auth
  runtime conformance contract shared by IO, Node, and Fetch host tests.
- Export the browser-shaped WebAuthn conformance contract and add a focused
  plugin helper for independently exercising passkey registration,
  authentication, replay defenses, and sanitized failures.
- Use plugin terminology consistently across Routed auth endpoint mounting and
  management internals, and update public examples to compose typed client
  plugins through `AuthClient`.
- Enforce configured verified-email and account-availability policy before
  issuing or resolving Routed sessions, while retaining generic auth-flow
  status handling.
- Complete a verified WebAuthn assertion by issuing a normal server-side
  session through the plugin session-control boundary.
- Add authenticated email-change request and confirmation routes with
  reauthentication, browser/CSRF protections, one-time delivery tokens, and
  session/JWT revocation after a successful change.
- Add authenticated linked-account listing/unlinking and account deletion
  routes. Deletion composes plugin-owned data contributors before the core
  transactional purge and revokes sessions/JWT versions.
- Add the CSRF-protected `/webauthn/credentials/rename` route contributed by
  `WebAuthnPlugin`.
- Make self-service account deletion retain an unavailable tombstone until a
  store retention job explicitly purges it.
- Automatically mount the opt-in `/auth/admin/...` API, enforce Admin bans at
  sign-in/session boundaries, and provide rotating server-session identity
  replacement for guarded impersonation.

- Automatically exposes the typed WebAuthn registration, assertion, passkey
  listing, and deletion endpoints contributed by `WebAuthnPlugin`, with the
  existing session, browser-origin, CSRF, and rate-limit boundary handling.
- Keep external JWT middleware independent from Routed's private session-token
  version claim; Routed-issued JWT sessions continue validating that claim in
  `AuthManager`.
- Preserve the initiating credentials provider through two-factor challenges,
  and include the OAuth provider in account-link lifecycle events.
- Automatically register opt-in plugin endpoint descriptors and add the
  complete `/auth/organization/...` API with shared browser, CSRF, session,
  rate-limit, and public-error handling.
- Add tenant-aware Haigate membership, permission, and resource-owner helpers
  without promoting organization roles into global principal roles.
- Add API-key lifecycle routes and `apiKeyAuthentication` middleware. API keys
  use `X-API-Key` or `Authorization: ApiKey`, expose scopes through request
  metadata, and never persist raw secrets.
- Add the opt-in `POST /auth/api-keys/exchange` route and typed client helper
  for creating a server-side session from an API-key header.
- Normalize HTTPS scheme checks when setting or expiring trusted-device and
  step-up cookies so sensitive tokens remain marked `Secure`.
- Sanitize JWT middleware challenge descriptions so callback diagnostics cannot
  disclose paths or other internal details through `WWW-Authenticate`.
- Added opt-in TOTP two-factor routes for enrollment, activation, verification,
  recovery-code use/regeneration, status, and disablement, with browser and
  CSRF protections.
- Direct recovery-code verification now shares the account-level TOTP lockout,
  preventing unlimited invalid recovery-code guesses.
- Credential sign-ins with enabled TOTP now return a typed pending challenge;
  `POST /auth/2fa/challenge/verify` issues the session after TOTP validation.
- Added optional trusted-device cookies for completed TOTP challenges and a
  CSRF-protected route to revoke all trusted devices.
- Added `POST /auth/2fa/challenge/recovery-code` and its typed client helper
  for atomic pending recovery-code sign-ins.
- Added step-up verification and revoke routes, HTTP-only proof cookies, and
  `AuthManager.requireTwoFactorStepUp` for sensitive actions.
- Applied the configured global auth rate limiter to all state-changing 2FA
  routes, including pending challenge verification.
- Register 2FA routes independently of the initial plugin configuration so
  managerOf-based config reloads can activate them without rebuilding routes.
- Revoke configured two-factor trusted-device tokens when routed password reset
  and password-change flows replace credentials.
- Resume the original credential provider and user context after two-factor
  challenge completion, including callback-backed providers.
- Added server-session management routes for listing active sessions, revoking
  one session, and revoking all other sessions. Session responses exclude token
  digests, and JWT session-management routes remain deferred.

- Added per-user JWT versioning through `AuthStore.jwtVersions`. Routed-issued
  JWTs now carry a protected version claim; password reset and password change
  rotate that version, invalidate old cookies/bearer tokens, and allow newly
  issued tokens to authenticate.
- Enabled password reset and password change routes for JWT sessions with the
  same browser protections, CSRF checks, rate limits, and generic errors.
- Added the server-session `POST /auth/password/change` route with CSRF and
  browser protections, current-password reauthentication, and session
  revocation.

- Added opt-in password-reset request and confirmation routes backed by the
  typed `AuthStore`, application-owned delivery callbacks, generic
  account-enumeration-safe responses, rate limiting, and server-session
  revocation.
- Added typed auth rate-limit enforcement across credentials, registration,
  email, OAuth, and custom callback boundaries.
- Added origin and Fetch Metadata protection for state-changing credential,
  email, registration, and signout routes.
- Reject malformed browser origins containing user-info or path/query data
  instead of normalizing them into trusted hosts.
- Added stateful/property regression coverage for session rotation, concurrent
  session refresh, revocation, replay attempts, and malformed cookies.
- Redacted provider tokens and nested credential-like fields before publishing
  auth events, including provider, user, session, profile, and payload
  projections.
- Bound OAuth token-exchange and user-info failures at callback routes so
  upstream parser and transport details do not escape as public errors.
- Routed OAuth flows now persist and atomically consume typed authorization
  challenges through `AuthStore`.
- Routed OAuth flows now bind the durable challenge to a short-lived,
  HttpOnly browser state cookie, preventing login-CSRF callbacks from another
  browser.
- Routed email verification now binds the magic link to a short-lived,
  HttpOnly browser state cookie, preventing login-CSRF callbacks from another
  browser.

## 0.2.0

- Auth managers now expose a composed `AuthRuntime` backed by the required
  typed `AuthStore`.
- Breaking: removed the flat auth adapter contract; `AuthOptions` requires
  `store`, and credential/email/OAuth flows use typed store domains directly.
- Hardened OAuth/OIDC flows with state, nonce, issuer, audience, expiry, and
  signed-token validation where applicable.
- Rotated sessions after login and kept raw JWTs out of session responses by
  default.
- Added bounded provider request timeouts and generic public error responses.
- Remove the unused schema-driven auth spec and its `json_schema_builder`
  dependency; typed auth provider instances remain the application contract.
- Remove the map/schema-based built-in provider registry and make
  `AuthConfig.defaults()` the provider's typed configuration fallback.
- Remove the duplicate internal provider implementations; provider APIs are
  exported from `server_auth` and are instantiated directly.

## 0.1.0

- Restored `routed_auth` as the Routed-specific auth integration package.
- Moved Routed auth glue out of `routed` into this package.
- Added `ensureRoutedAuthProviderRegistered()` for `routed.auth` provider registration.
