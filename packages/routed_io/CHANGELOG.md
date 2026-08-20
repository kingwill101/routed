## Unreleased

- Verify native `dart:io` request handling against the public Routed auth
  runtime conformance contract.

## 0.1.0

- Add `serveIo(...)` and `serveSecureIo(...)` boot helpers for Routed apps.
- Value edge: `portableRequestFromIo`, `writePortableResponseToIo`,
  `dispatchIoExchange` → `Engine.handlePortable`.
- `IoHttpConnection.toPortableRequest()` helper.
- `IoServerTransport.portableEdge` / `serveIo(portableEdge: …)` for parity
  testing with Node-style portable dispatch (default remains native fast path).
