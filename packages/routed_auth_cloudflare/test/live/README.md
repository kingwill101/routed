# Live D1 conformance harness

This harness is deliberately separate from local tests. It runs the same
`AuthStoreConformanceSuite` against a real `AUTH_DB` Worker binding and removes
each isolated table prefix after its case completes.

1. Create a temporary D1 database.
2. Replace the database name and ID placeholders in `wrangler.jsonc`.
3. From `packages/routed_auth_cloudflare`, compile and run the Worker:

   ```bash
   dart compile js test/live/live_d1_worker.dart -o build/live_d1_worker.js
   npx wrangler dev --config test/live/wrangler.jsonc
   curl -X POST http://localhost:8787/conformance
   ```

4. Confirm every result reports `passed: true`, then delete the temporary D1
   database.

This checkout does not treat compilation or local Wrangler emulation as live
D1 validation. A deployed or remote-bound run is required before reporting the
adapter as validated against Cloudflare.
