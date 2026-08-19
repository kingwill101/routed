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
