## 0.1.1

- Aligned session configuration and contract dependencies with the current
  server runtime.
- Invalidated rotated or destroyed session IDs and bound signed/encrypted
  cookie payloads to their cookie names.
- Preserved filesystem sessions with non-expiring options and isolated cookie
  options between sessions.
- Remove the unused `server_cache` runtime dependency; cache-backed sessions
  continue to accept a `server_contracts` repository directly.

## 0.1.0
- Initial extraction from server_data/src/sessions (PR G)
