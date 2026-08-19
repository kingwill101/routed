---
name: routed-io
description: Maintain, extend, document, test, or troubleshoot the routed_io subsystem in the Routed Dart monorepo. Use when a task touches routed_io APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_io

This skill is the complete working guide for the `routed_io` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_io`
- **Directory:** `packages/routed_io`
- **Version in this checkout:** `0.1.0`
- **Role:** `dart:io` server transport
- **Purpose:** The dart:io host transport for Routed. It maps HttpRequest/HttpResponse and native socket connections into routed_core transport contracts.

### Public API

- `serveIo` and `serveSecureIo` bind a VM HTTP(S) server and return a closeable server handle.
- `IoServerTransport`, `IoHttpConnection`, `IoRequestAdapter`, and `IoResponseAdapter` implement native request/response and streaming paths.
- `dispatchIoExchange` and `portableRequestFromIo` provide the buffered portable value edge.
- The native serve path uses `Engine.handleConnection` for streaming and websocket behavior; `portableEdge: true` forces the buffered path.
- The host capability is `HostCapabilities.ioProcess`.

### Public imports

- `package:routed_io/routed_io.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- Depend on routed_core plus routed_io for a Dart VM server.
- Use native serve by default; use the portable value edge for custom loops or compatibility paths that need buffered responses.
- Keep this package out of Node, Bun, Deno, Workers, Vercel, and Netlify builds.

### Known hazards

- Do not move dart:io types into routed_core or feature adapters.
- Close the returned server handle and test graceful shutdown.
- Test both streaming/native connection and portable buffered dispatch when changing adapters.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';

final engine = await Engine.create(providers: Engine.defaultProviders);
engine.get('/', (ctx) => ctx.string('ok'));
final handle = await serveIo(engine, host: '127.0.0.1', port: 8080);
await handle.close();
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_io`.
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

Cover bind/serve, secure options, request/response adapters, connection streaming, websocket handoff, portable dispatch, and shutdown.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_io
dart analyze --fatal-infos packages/routed_io
dart test packages/routed_io/test
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
