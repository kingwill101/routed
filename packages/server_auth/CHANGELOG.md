## Unreleased

- Hardened OIDC/JWT verification with required claims, issuer and audience
  checks, nonce support, and bounded JWKS requests.
- Sanitized public auth model serialization so secrets and tokens are not
  exposed accidentally; private persistence retains the fields it needs.
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
