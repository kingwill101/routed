## 0.2.0

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
