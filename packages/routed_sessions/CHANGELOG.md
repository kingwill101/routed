## 0.2.1 - 2026-08-25

- Hardened default Routed session cookies with `Secure`, `HttpOnly`, and
  `SameSite=Lax`; local HTTP deployments must explicitly opt out with
  `secure: false`.
- Migrated the adapter to `very_good_analysis` and completed public Dartdoc
  coverage for the session context helpers, middleware, configuration, and
  provider APIs.

## 0.2.0

- **Breaking:** Type `SessionConfig.store` and the optional
  `sessionMiddleware` store parameter as `SessionStore`; remove runtime casts
  and untyped-store compatibility paths.
- Added explicit session configuration and public exports for the underlying
  session runtime.
- Aligned session middleware and flash-message helpers with the current
  session store APIs.

## 0.1.0
- Initial adapter (PR G)
