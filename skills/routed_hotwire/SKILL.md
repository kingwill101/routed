---
name: routed-hotwire
description: Maintain, extend, document, test, or troubleshoot the routed_hotwire subsystem in the Routed Dart monorepo. Use when a task touches routed_hotwire APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_hotwire

This skill is the complete working guide for the `routed_hotwire` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_hotwire`
- **Directory:** `packages/routed_hotwire`
- **Version in this checkout:** `0.1.4`
- **Role:** Turbo and Stimulus response helpers
- **Purpose:** Turbo and Stimulus helpers for server-rendered interactive applications. It adds response/request interpretation, Turbo Streams, websocket stream hubs, and context extensions without registering a provider.

### Public API

- `TurboRequestKind` and `TurboRequestInfo` classify Turbo frame, stream, navigation, and ordinary requests.
- `TurboResponse` and `TurboResponseContext` provide Turbo-aware redirects, frames, flash messages, and response headers.
- `TurboStreamAction`, `turboStreamAppend`, and the Turbo Streams helpers create stream responses.
- `TurboStreamHub`, `TurboStreamSocketHandler`, `WebSocketTurboConnection`, and `TurboTopicResolver` handle websocket stream delivery.
- The package also exposes Stimulus controller scaffolding/assets and testing helpers layered over routed_testing/server_testing.

### Public imports

- `package:routed_hotwire/routed_hotwire.dart`

### Runtime package dependencies

- `routed_core`
- `routed_logging`
- `routed_views`

### Composition rules

- Import the package alongside routed or routed_core; the package extends EngineContext and does not add an Engine provider.
- Use Turbo response helpers for HTML navigation and stream updates; keep application authorization for stream topics explicit.
- Use routed_testing to exercise Turbo headers, stream bodies, optimistic updates, and websocket behavior.

### Known hazards

- Do not treat a Turbo request as authorization; validate the user and topic before broadcasting.
- Keep stream names stable because browser subscriptions and websocket routing depend on them.
- Preserve correct content types and Turbo-specific status/redirect semantics.

## Minimal usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

engine.post('/notes', (ctx) => ctx.turboStream(
  turboStreamAppend(target: 'notes', html: '<li>new</li>'),
));
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_hotwire`.
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

Cover request classification, stream rendering, append/replace/remove actions, redirects/flash, Stimulus asset output, and websocket hub lifecycle.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_hotwire
dart analyze --fatal-infos packages/routed_hotwire
dart test packages/routed_hotwire/test
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
