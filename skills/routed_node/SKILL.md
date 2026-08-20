---
name: routed-node
description: Maintain, extend, document, test, or troubleshoot the routed_node subsystem in the Routed Dart monorepo. Use when a task touches routed_node APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_node

This skill is the complete working guide for the `routed_node` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_node`
- **Directory:** `packages/routed_node`
- **Version in this checkout:** `0.2.0`
- **Role:** Node.js, Bun, Deno, and Fetch/Cloudflare edge transports and bindings
- **Purpose:** The multi-host JavaScript and edge transport. It supports explicit Node.js, Bun, Deno, Cloudflare Workers, Vercel, and Netlify entrypoints over the same routed_core portable contracts.

### Public API

- `serveNode`, `serveBun`, and `serveDeno` run listener hosts.
- `cloudflare.dart`, `vercel.dart`, and `netlify.dart` expose Fetch-style bootstrap functions; Cloudflare uses `defineCloudflareFetchAsync`.
- `dispatchFetchExchange`, `dispatchFetchConnection`, and `dispatchNodeExchange` map buffered/streaming host requests to Engine portable handlers.
- `NodeHttpConnection`, `NodeRequestAdapter`, `NodeResponseAdapter`, and `NodeServerTransport` implement Node streaming and websocket paths.
- Cloudflare wrappers expose value-oriented environment, D1, Durable Objects, R2, Queues, service bindings, Workflows, Containers, and execution-context helpers.
- Capability differences are intentional: Node/Bun/Deno support listener websockets, Cloudflare supports the Worker websocket bridge, and Vercel/Netlify expose no server-side upgrade API.

### Public imports

- `package:routed_node/bun.dart`
- `package:routed_node/cloudflare.dart`
- `package:routed_node/deno.dart`
- `package:routed_node/netlify.dart`
- `package:routed_node/node.dart`
- `package:routed_node/routed_node.dart`
- `package:routed_node/vercel.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- Import only the runtime entrypoint required by the deployment target; do not import routed_io in JavaScript builds.
- Use routed_core plus routed_node and keep application route/provider code host-neutral.
- Use Cloudflare binding wrappers through the request context; native Dart VM calls report UnsupportedError for unavailable bindings.

### Known hazards

- Do not promise websocket support on Vercel or Netlify; route persistent realtime traffic to a supported host/service.
- Preserve streaming vs buffered dispatch and Fetch Request/Response semantics.
- Test each runtime entrypoint separately, including unsupported-host capability flags and JS compilation.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/node.dart';

final engine = await Engine.create(providers: Engine.defaultProviders);
final handle = await serveNode(engine, host: '0.0.0.0', port: 8080);
await handle.close();
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_node`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a `lib/src` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

Cover runtime identity, listener lifecycle, Fetch exchange/connection dispatch, Node adapters, websocket upgrades, Cloudflare binding wrappers, and host capability matrices.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_node
dart analyze --fatal-infos packages/routed_node
dart test packages/routed_node/test
```

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use `routed` for the full provider catalogue or
  `routed_core` plus explicit adapters for slim compositions.
- Routed adapters depend on `routed_core` and matching `server_*` runtimes;
  they must not depend on the batteries-included `routed` facade.
- Host I/O belongs in `routed_io`, `routed_node`, or `server_native`, not in
  feature adapters.
- Framework-agnostic `server_*` implementations must not import Routed from
  `lib/`.
