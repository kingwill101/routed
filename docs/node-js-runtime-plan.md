# Detailed Plan: Routed Node/JavaScript Runtime Direction

## 1. Objective

Evolve `routed_node` into a predictable, testable multi-runtime host layer for
Routed applications while preserving Routed's framework ownership:

- `routed_core` owns routing, middleware, DI, request context, and the portable
  request/response boundary.
- `routed_node` owns JavaScript-host I/O, runtime entrypoints, native bridges,
  deployment shims, and capability reporting.
- Applications continue to use the same `Engine`, routers, middleware,
  controllers, providers, and `Engine.ws(...)` routes across supported hosts.

The target is not identical behavior on every platform. The target is a shared
application pipeline with explicit runtime boundaries and honest capability
claims.

## 2. Current Baseline

### Implemented and verified

- Portable HTTP request/response contracts in `routed_core`.
- Node HTTP listener and raw WebSocket upgrade handling.
- Bun `Bun.serve` HTTP and native `server.upgrade` WebSocket echo.
- Cloudflare Fetch HTTP, streaming responses, and `WebSocketPair` echo.
- Lazy Fetch engine initialization for Worker-style hosts.
- CLI-generated Cloudflare and Netlify deployment wrappers.
- Runtime/capability metadata and typed host extensions.
- Runtime matrix documentation.
- Separate host entrypoints for Node, Bun, Deno, Cloudflare, Vercel, and
  Netlify.

### Implemented but not fully verified

- Deno `Deno.upgradeWebSocket` bridge: compiled and statically analyzed, but no
  reliable Deno CLI is currently available for live validation.
- Vercel and Netlify Fetch behavior beyond the current deployed HTTP checks.
- Full lifecycle and shutdown behavior for Bun, Deno, and Cloudflare sockets.
- Protocol edge cases across all JavaScript WebSocket transports.

### Reference findings

- `third_party/osrv` is the primary architectural reference for runtime
  boundaries, capability contracts, native upgrade timing, shutdown tracking,
  and black-box runtime tests.
- `third_party/dart_edge` is archived and should be treated as historical
  evidence for edge bindings, generated shims, and CLI deployment ideas only.
- Neither repository should become a dependency or a source of copied
  implementation code.

## 3. Design Principles

1. **Framework/core ownership stays stable.** Do not move routing or middleware
   into `routed_node`.
2. **Explicit entry models.** Listener runtimes and Fetch-export runtimes have
   different lifecycle and shutdown semantics and must remain separate.
3. **Native-first host bridges.** Use each host's actual upgrade and response
   model rather than emulating Node everywhere.
4. **Capabilities mean implemented support.** A host API existing in theory is
   not enough to set `webSocket: true`.
5. **No adapter registry.** Shared behavior contracts and small internal helper
   types are acceptable; runtime discovery and a universal adapter registry are
   not.
6. **One application pipeline.** Host-specific code should translate at the
   boundary and then invoke the same Routed engine pipeline.
7. **Lifecycle is observable and bounded.** Listener shutdown must account for
   active requests, WebSocket sessions, and tracked background work.
8. **Deployment owns bootstrap.** The CLI should generate compilation output,
   host wrappers, and staging configuration where practical.
9. **Test behavior, not implementation shape.** Cross-runtime tests should
   assert HTTP, streaming, upgrade, message, close, error, and shutdown
   semantics.

## 4. Target Runtime Matrix

| Runtime | Entry model | HTTP | Streaming | WebSocket | Filesystem | Background work | Verification target |
|---|---|---:|---:|---:|---:|---:|---|
| Node.js | listener | yes | yes | yes | yes | yes | live process + protocol suite |
| Bun | listener | yes | yes | yes | yes | yes | live process + protocol suite |
| Deno | listener | yes | yes | yes when API exists | yes | yes | live process + protocol suite |
| Cloudflare Workers | Fetch export | yes | yes | yes | no | request-scoped only | local Wrangler + deployed smoke |
| Vercel | Fetch/function export | yes | yes | no | host-dependent | host-dependent | compiled Fetch contract; explicit unsupported upgrade |
| Netlify | Fetch/function or Edge export | yes | yes | no | host-dependent | request-dependent | deployed HTTP contract; explicit unsupported upgrade |

The public matrix should distinguish:

- **supported**: adapter implemented and behavior verified;
- **host-dependent**: adapter can only claim support after runtime probing or a
  deployment-specific contract is satisfied;
- **unsupported**: the host entrypoint intentionally rejects or declines the
  feature.

## 5. Workstreams

## Workstream A: Freeze the Host Boundary Contract

### A1. Define the internal bridge responsibilities

Document and enforce five responsibilities for every host adapter:

1. request conversion;
2. response conversion;
3. WebSocket upgrade preparation;
4. connected WebSocket session conversion;
5. lifecycle/resource accounting.

These are behavioral responsibilities, not a common adapter class hierarchy.

### A2. Audit portable-core leakage

Inventory all `dart:io` and synthetic `HttpRequest` use in portable paths.
Prioritize:

- `Engine.handlePortable`;
- `Engine.handleConnection`;
- `AdapterHttpBridge`;
- portable WebSocket request handling;
- response status/header/body commitment.

Deliverable: a table identifying which paths are transitional, which are safe
for Node/Bun/Deno/Fetch, and the next removal candidate.

### A3. Clarify host context and extension semantics

Ensure every request entering `routed_node` carries:

- runtime identity;
- entry model;
- capability snapshot;
- typed host extension;
- native request/execution context where available.

Add tests proving that context is available to normal HTTP handlers, streaming
handlers, WebSocket handlers, and error paths.

### Acceptance criteria

- No host package type is imported by `routed_core`.
- Every public runtime entrypoint has a documented capability object.
- Every host request has a deterministic runtime context.
- Portable and native paths expose the same application-visible routing result.

## Workstream B: Harden the WebSocket Contract

### B1. Define common semantic requirements

For each supported host, specify and test:

- upgrade request detection;
- route matching and middleware execution;
- selected subprotocol validation;
- handler `onOpen` timing;
- text message delivery;
- binary message delivery;
- application close;
- peer close;
- handler error behavior;
- rejected path behavior;
- malformed handshake behavior;
- shutdown behavior.

Do not require identical close codes where the host does not expose them.

### B2. Improve the shared socket abstraction

Review `RoutedWebSocket` and `WebSocketUpgradeRequest` for the minimum portable
surface:

- stream of text/binary messages;
- `add`/send;
- close with optional code/reason;
- close observability where available;
- explicit unsupported behavior for ping/pong, backpressure, compression, and
  host-specific limits.

Document what is intentionally not portable.

### B3. Add lifecycle/resource tracking

Introduce an internal host resource tracker, or extend the existing host handle
without creating a second public lifecycle bus. It should track:

- active HTTP requests;
- pending upgrade negotiations;
- active WebSocket sessions;
- background tasks registered by the host.

Listener `close()` must:

1. stop new accepts;
2. reject or drain pending requests deterministically;
3. close active sockets with `1001` where supported;
4. await tracked resources;
5. publish the existing Routed lifecycle stop event.

### Acceptance criteria

- No accepted WebSocket session becomes an untracked background task.
- Upgrade rejection never leaves a pending token or socket registry entry.
- Listener shutdown tests complete without leaked handles.
- Fetch-export runtimes do not invent a fake process-wide shutdown handle.

## Workstream C: Node.js Runtime

### C1. Preserve and harden the raw upgrade path

Use the HTTP server `upgrade` event as the authoritative WebSocket boundary.
Keep the application route pipeline separate from the raw socket handshake.

Add tests for:

- missing `Upgrade` header;
- missing `Connection: upgrade` token;
- unsupported WebSocket version;
- missing key;
- invalid subprotocol;
- rejected route;
- raw `101` response misuse;
- invalid UTF-8;
- fragmentation;
- masking;
- control frame constraints;
- peer close and server close;
- shutdown with active sessions.

### C2. Improve build/startup integration

Make the CLI/example Node build automatically handle the required standalone
JavaScript liveness behavior (`--server-mode` and the necessary Node bootstrap)
without requiring manual concatenation.

Acceptance criteria:

- `routed deploy`/`routed dev` can produce a runnable Node artifact.
- Node runtime does not depend on unresolved Dart Futures to keep the event loop
  alive.
- The generated artifact has a documented Node version requirement.

## Workstream D: Bun Runtime

### D1. Replace the happy-path bridge with explicit upgrade state

Adopt the `osrv` pattern:

1. allocate a monotonically increasing token;
2. store pending handler/context by token;
3. call `server.upgrade(request, {data: token})`;
4. return `undefined` after successful upgrade;
5. resolve token from Bun's server-level `open` callback;
6. move session to active set;
7. route `message`, `close`, and `error` callbacks to that session;
8. remove all state on rejection, close, or error.

The current bridge already proves the basic route, but this state machine should
be made explicit and robust.

### D2. Add Bun protocol and lifecycle tests

Add live integration coverage for:

- text echo;
- binary echo;
- selected subprotocol;
- close code/reason if Bun exposes them;
- rejected upgrade;
- two concurrent sockets;
- shutdown race;
- upgrade rejection after shutdown begins;
- pending token cleanup.

### D3. Align `ServerHandle.close()` with active sockets

Extend `JsServerHandle` or a Bun-specific internal handle so `close()` stops the
Bun server and waits for active sessions to close. Preserve the existing
`ServerHandle` public shape.

Acceptance criteria:

- Bun matrix remains `webSocket: true` only when the full contract passes.
- The live Bun test suite exits cleanly with no stderr output.
- No process-level polling or timer is used as a substitute for resource
  tracking.

## Workstream E: Deno Runtime

### E1. Complete the native Deno upgrade path

Use `Deno.upgradeWebSocket(request)` as a request-scoped outcome:

1. execute the Routed pipeline;
2. match a WebSocket route;
3. create the native socket/response pair only after upgrade acceptance;
4. return the native response;
5. attach socket event handlers;
6. await socket open before invoking `onOpen`;
7. track and close sessions during listener shutdown.

Do not model Deno as Node's raw `upgrade` event.

### E2. Add a real Deno toolchain to CI

Provision a supported Deno CLI or make it an explicit optional integration job.
The job must compile the Dart entry and run the generated JS under Deno.

Add tests for:

- HTTP and streaming;
- upgrade and echo;
- binary message;
- subprotocol;
- peer close;
- application close;
- shutdown;
- missing `Deno.upgradeWebSocket` capability behavior.

### Acceptance criteria

- Deno's matrix row says live verified only after a process test passes.
- Host probing and capability reporting agree.
- Deno failures produce deterministic HTTP responses before upgrade.

## Workstream F: Cloudflare and Fetch Export Runtimes

### F1. Stabilize the Fetch lifecycle

Keep lazy engine creation for Worker-style entrypoints. Define clear rules for:

- first request initialization;
- concurrent first requests;
- initialization failure caching or retry;
- request-scoped execution context;
- response commitment;
- streaming body failures;
- WebSocket upgrade response construction.

Add a single-flight initialization test so concurrent requests do not create
multiple engines.

### F2. Cloudflare WebSocket contract

Add tests for:

- typed `WebSocketPair` access;
- handshake response status and headers;
- `accept()` invocation;
- text and binary messages;
- protocol selection;
- close and error events;
- malformed upgrade request;
- handler error after upgrade.

Keep Cloudflare `webSocket: true` only for the native Worker upgrade path.

### F3. Vercel and Netlify unsupported behavior

Make unsupported upgrades explicit and deterministic:

- capability remains `false`;
- `/ws` does not hang;
- the adapter returns the documented response/status;
- documentation names the platform limitation;
- managed real-time providers are recommended for Netlify-style hosting.

### Acceptance criteria

- No top-level unresolved initialization future can hang a Worker request.
- Streaming and buffered Fetch responses share header/status semantics.
- Unsupported hosts never claim native WebSocket support.

## Workstream G: Compiler and Deployment Profiles

### G1. Separate build policies

Define host build profiles:

| Profile | Hosts | Key rules |
|---|---|---|
| listener-js | Node, Bun, Deno | standalone JS, host liveness/bootstrap, source maps |
| fetch-worker | Cloudflare | no server-mode, Worker wrapper, lazy factory |
| fetch-function | Vercel, Netlify | Fetch export, host-specific ESM shim, route config |

Do not reuse `dart_edge`'s unconditional `--server-mode` approach for all
platforms.

### G2. Generated artifacts

The CLI should own:

- staging directory creation;
- Dart compilation;
- generated Dart entrypoint;
- JavaScript wrapper;
- package manifest and host config;
- deployment command;
- cleanup or reproducible retained output.

Add dry-run snapshots for each generated wrapper.

### G3. Node bootstrap

Make Node preamble/liveness handling automatic in the generated Node workflow.
Document when the output is expected to run under Node, Bun, or Deno rather than
assuming a generic JavaScript executable.

### Acceptance criteria

- Each target uses the correct compiler flags.
- Generated wrappers are deterministic and testable without deployment.
- A user does not need to write an application bootstrap file for supported
  CLI-managed deployments.

## Workstream H: Shared Contract Test Suite

Create a reusable test harness with host-specific runners.

### Portable contract tests

Run on VM with fakes:

- request conversion;
- headers, cookies, and multi-value headers;
- body streaming and buffering;
- response status and headers;
- error conversion;
- capability serialization;
- lifecycle event ordering.

### Listener process tests

Run where tools are installed:

- Node;
- Bun;
- Deno.

Each process test should use the same application fixture and endpoint set:

- `/health`;
- `/capabilities`;
- `/echo`;
- `/stream`;
- `/ws`;
- `/ws-protocol`;
- `/shutdown` or a controlled close endpoint.

### Fetch/export tests

Run JS-host tests for:

- Cloudflare Worker-compatible request/response objects;
- Vercel Fetch behavior;
- Netlify Fetch behavior;
- unsupported WebSocket outcomes.

### Protocol tests

Where the host allows raw control:

- frame masking;
- fragmentation;
- UTF-8;
- close frames;
- ping/pong;
- oversized payloads;
- concurrent sessions.

Record host-specific deviations rather than weakening the shared assertions.

## 6. Documentation Deliverables

Update these documents as implementation progresses:

- `docs/portable-host-architecture.md`
  - remove stale claims;
  - document listener versus Fetch-export flow;
  - document WebSocket boundaries and shutdown semantics.
- `docs/node-js-runtime-catalog.md`
  - keep source findings and roadmap synchronized.
- `packages/routed_node/README.md`
  - runtime matrix with verification status;
  - public imports;
  - capability semantics;
  - host limitations.
- `packages/routed_node/example/api/README.md`
  - commands for Node, Bun, Deno, Cloudflare, and Netlify;
  - explicit live-validation requirements.
- `packages/routed_node/CHANGELOG.md`
  - record runtime and capability changes.
- CLI documentation
  - generated deployment/build behavior;
  - host profile differences;
  - dry-run output.

Every capability claim must identify whether it is:

- unit-tested;
- compile-tested;
- locally process-tested;
- deployed smoke-tested.

## 7. Suggested Commit Sequence

Keep commits reviewable and reversible:

1. `docs: catalog node and edge runtime references`
2. `refactor(routed-node): formalize host bridge context`
3. `test(routed-node): add shared runtime contract fixtures`
4. `feat(routed-node): harden node websocket lifecycle`
5. `feat(routed-node): track bun websocket sessions`
6. `test(routed-node): verify bun protocol and shutdown behavior`
7. `feat(routed-node): complete deno websocket lifecycle`
8. `test(routed-node): add live deno process coverage`
9. `feat(routed-node): stabilize cloudflare fetch initialization`
10. `test(routed-node): expand fetch host capability coverage`
11. `refactor(routed-cli): split listener and fetch build profiles`
12. `docs(routed-node): publish verified runtime matrix`

Do not combine unrelated OpenAPI, CLI, deployment, and WebSocket changes unless
they are required for one host profile.

## 8. Verification Gates

### Gate 1: Static correctness

```bash
dart format --output=none --set-exit-if-changed packages/routed_core packages/routed_node packages/routed_cli
dart analyze packages/routed_core packages/routed_node packages/routed_cli
git diff --check
```

### Gate 2: Core and host tests

```bash
dart test packages/routed_core/test
 dart test packages/routed_node/test
 dart test packages/routed_cli/test
```

### Gate 3: JavaScript compilation

Compile every changed JS entrypoint:

```bash
dart compile js <node-entry.dart> -o /tmp/routed-node.js -O2
dart compile js <bun-entry.dart> -o /tmp/routed-bun.js -O2
dart compile js <deno-entry.dart> -o /tmp/routed-deno.js -O2
```

### Gate 4: Process validation

When available:

```bash
node <node-artifact.js>
bun <bun-artifact.js>
deno run --allow-net <deno-artifact.js>
```

Verify HTTP, streaming, WebSocket, close, and shutdown behavior.

### Gate 5: Deployment smoke tests

- Cloudflare: deploy and test `/health`, `/capabilities`, `/stream`, and `/ws`.
- Netlify: test `/health`, `/capabilities`, and `/stream`; verify unsupported
  `/ws` behavior.
- Vercel: test Fetch response and unsupported upgrade behavior.

### Gate 6: Documentation and repository hygiene

- runtime matrix matches actual test evidence;
- generated artifacts are ignored or intentionally staged;
- third-party references remain untracked/local-only;
- no unrelated files are included in a commit;
- no stale capability claims remain.

## 9. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Dart JS output behaves differently by host | Compile and run each host-specific entry separately |
| Top-level async initialization hangs Workers | Lazy, request-attached, single-flight initialization |
| Bun upgrade occurs outside fetch lifecycle | Tokenized pending/active session state |
| Deno API differs across versions | Preflight probes plus versioned CI runtime |
| WebSocket close semantics differ | Assert portable events; record host-specific close-code limits |
| `routed_core` remains tied to synthetic IO bridge | Keep a shrinking migration table and add native portable tests |
| Capability flags drift from reality | Require matrix evidence before changing a flag |
| Generated deployment shims become user burden | Keep generation in CLI and snapshot-test wrappers |
| Third-party code is copied accidentally | Treat local repositories as design references only |
| Large mixed commits obscure regressions | Follow the atomic commit sequence |

## 10. Definition of Done

The runtime direction is complete when:

- Node, Bun, and Deno listener runtimes pass the shared HTTP/streaming/WebSocket
  process contract in supported CI environments;
- Cloudflare passes Fetch, streaming, and WebSocket smoke tests;
- Vercel and Netlify explicitly pass HTTP/streaming tests and explicitly reject
  unsupported native WebSocket behavior;
- all capability flags match verified behavior;
- active listener WebSocket sessions participate in shutdown;
- Fetch initialization cannot hang because of unowned top-level Futures;
- CLI build/deploy profiles use host-appropriate compiler flags and generated
  shims;
- runtime docs and the compatibility matrix identify evidence level for every
  claim;
- the core package remains free of Node/Bun/Deno/Worker host types;
- all changes are split into focused, reviewable commits;
- the worktree is clean after verification.
