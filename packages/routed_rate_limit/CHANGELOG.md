## 0.1.1 - 2026-08-25

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.
- Clarified rate-limit middleware, typed provider, auth adapter, key
  resolution, and event semantics; portable IP-policy tests now provide a
  client address.

## 0.1.0

- Export namespaced `AuthRateLimitOperation` values so opt-in auth features can
  contribute operations without extending the legacy core enum.

- Updated the rate-limit adapter documentation and provider setup examples for
  the current portable runtime.
- Aligned the adapter with the serialized, method-aware rate-limit runtime.
- Added `RoutedAuthRateLimiter` so existing rate-limit policies can enforce
  `server_auth` operations through `AuthOptions.rateLimiter`.
- Initial adapter (PR I)
