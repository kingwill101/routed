---
name: routed-core
description: Maintain, extend, document, test, or troubleshoot the routed_core subsystem in the Routed Dart monorepo. Use when a task touches routed_core APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_core

This skill is the complete working guide for the `routed_core` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_core`
- **Directory:** `packages/routed_core`
- **Version in this checkout:** `0.4.0`
- **Role:** Slim engine, routing, contexts, configuration, and lifecycle
- **Purpose:** The slim HTTP engine foundation: Engine, EngineContext, Router, request/response values, DI/container, lifecycle, providers, middleware, route metadata, and portable transport contracts.

### Public API

- `Engine.create()` boots `Engine.defaultProviders`; `Engine` owns routes, middleware, lifecycle, and transport dispatch.
- `EngineContext` exposes request-scoped services, response builders, typed state, context keys, and provider services.
- `Router`, `RouteBuilder`, controllers, route metadata, and middleware references define the routing surface.
- `ServiceProvider`, `TypedProvider`, `CoreServiceProvider`, `RoutingServiceProvider`, and `UploadsServiceProvider` define provider boot.
- `PortableRequest`, `PortableResponse`, `RequestAdapter`, `ResponseAdapter`, `ServerTransport`, `Engine.handlePortable`, and `Engine.handleConnection` form the host boundary.
- The public barrel also exposes configuration, lifecycle shutdown, network matching, trusted-proxy resolution, websockets, signals, and deep merge/copy utilities.

### Public imports

- `package:routed_core/routed_core.dart`
- `package:routed_core/signals.dart`

### Runtime package dependencies

- `server_contracts`

### Composition rules

- Use `Engine.defaultProviders` for a slim core app; append feature providers explicitly.
- Keep feature adapters on routed_core plus server_* packages. The core must not import the batteries-included routed facade.
- Keep host binding in routed_io, routed_node, or server_native; use the portable value/connection APIs for non-VM hosts.

### Known hazards

- Preserve provider ordering and lifecycle events; a provider that depends on another must boot after it.
- Do not add feature-specific services, storage, auth, or host sockets to core.
- When changing request/response or route contracts, test both direct Engine handling and the affected host adapter.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';

final engine = await Engine.create(
  providers: Engine.defaultProviders,
)..get('/health', (ctx) => ctx.json({'ok': true}));
await engine.serve(port: 8080);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_core`.
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

Cover provider boot, routing, middleware order, request/response conversion, context state, route metadata, portable dispatch, websocket/lifecycle behavior, and boundary purity.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_core
dart analyze --fatal-infos packages/routed_core
dart test packages/routed_core/test
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
