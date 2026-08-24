## Unreleased

- Adopt `very_good_analysis` and complete public API documentation for the
  Node, Fetch, and Cloudflare host integrations.

## 0.2.1

- Add `defineCloudflareFetchFactoryWithEnvironmentAsync` for typed Worker
  startup with Cloudflare bindings such as D1 and secrets.
- Add a sharded SQLite-backed `CloudflareDurableObjectStore` and
  `CloudflareDurableObjectStoreObject` for shared cache and distributed-lock
  state on Workers, including the locking contract used by
  `CacheRateLimiterBackend`.
- Preserve Cloudflare's `CF-Connecting-IP` through the Fetch bridge so
  portable request IP policies, including rate limiting, work on Workers
  without a socket remote address.

## 0.2.0

- Enumerate native Fetch headers at the portable request boundary and retain
  the actual bound Node listener port, including ephemeral-port listeners.
- Verify native Node and Cloudflare Fetch request handling against the same
  public Routed auth runtime conformance contract used by `routed_io`.
- Adopted null-aware collection elements in the Cloudflare Fetch binding
  serialization paths so the host adapter remains analyzer-clean.

- Fix D1 metadata decoding for Cloudflare's snake_case `rows_read` and
  `rows_written` fields, and align `served_by_primary` with Cloudflare's
  boolean contract while exposing the `served_by_colo` location.
- Added host-neutral Cloudflare bindings for Request `cf` metadata, the Cache
  API, R2 buckets, Queue producers, and Worker service bindings.
- Added host-neutral Cloudflare bindings for Container instances and
  Container-backed Durable Object controls, Workflow instances, and Secrets
  Store reads. Worker bindings are also available through `env.worker(...)`,
  including HTTP Fetch and RPC calls.
- Added Node runtime coverage for Cloudflare cache, R2 streaming objects,
  queue metrics, service-binding responses, Container controls, Workflow
  lifecycle operations, and Secrets Store reads.
- Expanded host integrations for Bun, Deno, Vercel, and Netlify while keeping
  the portable request/response boundary consistent across runtimes.
- Added listener WebSocket bridging and runtime capability reporting.
- Fetch-host failures now return a generic public error while retaining the
  diagnostic details for internal logging.
- Added the Cloudflare-specific `cloudflare.dart` binding surface for Worker
  environments, KV, D1, Durable Objects, alarms, and SQLite SQL storage.
- Added an end-to-end Cloudflare usage example covering D1, KV, and
  SQLite-backed Durable Objects.
- Added Routed-owned Cloudflare request and response wrappers so application
  code does not need `package:web` or `dart:js_interop`.
- Added text and JSON helpers for buffered Durable Object responses.
- Added host-neutral Durable Object `WebSocketPair`, hibernation socket
  methods, and message/close/error callback forwarding.
- Add `cloudflareTextBinding` so Worker text and secret bindings can be read
  through the public host-neutral API without `package:web` or JS interop.

## 0.1.0

- Initial Node.js host transport for Routed.
- Preferred value edge: `portableRequestFromNode`,
  `writePortableResponseToNode`, `dispatchNodeExchange` →
  `Engine.handlePortable`.
- Stream-sink path: `NodeRequestAdapter` / `NodeResponseAdapter` /
  `NodeHttpConnection` for `Engine.handleConnection`.
- `NodeServerTransport` + `serveNode` bind via Node `http.createServer`
  (JS interop; stubbed on the Dart VM).
- Sample API project under `example/api` (JSON items API, VM smoke,
  `serveNode` entry + `index.cjs` Node bootstrap).
