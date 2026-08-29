## Unreleased

- Widened the `storage_fs` dependency to `>=0.1.0 <1.0.0` so compatible 0.x
  filesystem adapters can resolve in the same application.

## 0.2.1 - 2026-08-25

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.
- Clarified the package-level cache workflow, typed store factories, and
  in-memory locking and storage behavior.
- Documented Redis, no-op, repository, and tag-scoped cache APIs and their
  operational boundaries.

## 0.2.0

- Replace map-based store configuration and string-driver resolution with
  concrete `Store` registration and typed `StoreConfiguration` factories.
- Made store-only-if-absent operations atomic across the file, Redis, array,
  and null stores.
- Corrected file-store TTL handling and namespaced tagged-cache keys to avoid
  cross-scope collisions.
- Made tag invalidation and file-lock operations consistently await their
  backing store writes.

## 0.1.0

- Initial extraction from `server_data/src/cache` (PR F)
