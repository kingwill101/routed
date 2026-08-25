## 0.1.2 - 2026-08-25

- Completed public API documentation and adopted the `very_good_analysis`
  lint baseline.
- Expanded the low-level README and API docs with policy strategy, backend
  atomicity, failover, and service evaluation guidance.

## 0.1.1

- Serialized cache-backed rate-limit updates so concurrent requests cannot
  consume the same quota state.
- Applied configured HTTP methods to catch-all and wildcard patterns.
- Remove the unused `server_cache` runtime dependency; cache-backed limiting
  continues to use the `Repository` and `LockProvider` contracts.

## 0.1.0
- Initial extraction from server_data/src/rate_limit (PR I)
