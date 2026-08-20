## Unreleased

- Mount phone-number send/verify operations from the opt-in server plugin and
  issue normal Routed sessions after successful verification.
- Apply opt-in captcha checks to credential sign-in/registration and
  breached-password checks to registration, reset, and password change while
  preserving generic HTTP failures and existing rate limits.
- Add `RoutedAuthDeploymentBinding` helpers to bind typed auth options, create
  the matching service provider, and apply explicit proxy policy to the Routed
  engine configuration.
- Publish `package:routed_auth/testing.dart` with a framework-neutral auth
  runtime conformance contract shared by IO, Node, and Fetch host tests.
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
