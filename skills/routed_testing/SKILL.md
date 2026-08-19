---
name: routed-testing
description: Maintain, extend, document, test, or troubleshoot the routed_testing subsystem in the Routed Dart monorepo. Use when a task touches routed_testing APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_testing

This skill is the complete working guide for the `routed_testing` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_testing`
- **Directory:** `packages/server_testing/routed_testing`
- **Version in this checkout:** `0.4.0`
- **Role:** Routed adapter for the upstream `server_testing` harness
- **Purpose:** Routed-specific testing helpers built on server_testing. It adapts Engine to in-memory and ephemeral-server transports and exposes property-testing-friendly clients.

### Public API

- `RoutedRequestHandler` bootstraps an Engine as a server_testing RequestHandler.
- `TransportMode.inMemory` and `TransportMode.ephemeralServer` switch transport without changing the test body.
- `TestClient.inMemory(handler)` issues requests through the in-memory adapter; server_testing provides assertions and client behavior.
- `TestCallback` and `EngineTestFunction` define reusable engine/client test callbacks.
- The adapter re-exports `RoutedTransport` and the testing helpers through both routed_testing.dart and testing.dart.

### Public imports

- `package:routed_testing/routed_testing.dart`
- `package:routed_testing/testing.dart`

### Runtime package dependencies

- `routed_core`
- `server_testing`

### Composition rules

- Construct the test Engine with the same providers as production; testing helpers do not automatically reproduce feature provider configuration.
- Use in-memory tests for fast route/middleware assertions and ephemeralServer for socket/transport integration.
- Use property_testing with TestClient to stress route parameters, middleware stacks, and response invariants.

### Known hazards

- Always close TestClient, RoutedRequestHandler, and Engine resources.
- Do not treat in-memory transport as proof of socket, TLS, streaming, or host-adapter behavior.
- Keep test assertions on status/body/headers and add an ephemeral transport case for transport-sensitive changes.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

final engine = await Engine.create();
engine.get('/ping', (ctx) => ctx.text('pong'));
final handler = RoutedRequestHandler(engine);
final client = TestClient.inMemory(handler);
final response = await client.get('/ping');
response.assertStatus(200).assertBodyContains('pong');
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_testing`.
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

Cover handler boot, in-memory requests, ephemeral server lifecycle, provider parity, transport failures, assertions, and property-based route coverage.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/server_testing/routed_testing
dart analyze --fatal-infos packages/server_testing/routed_testing
dart test packages/server_testing/routed_testing/test
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
