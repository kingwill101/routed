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
