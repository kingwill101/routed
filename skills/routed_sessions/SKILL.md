---
name: routed-sessions
description: Maintain, extend, document, test, or troubleshoot the routed_sessions subsystem in the Routed Dart monorepo. Use when a task touches routed_sessions APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_sessions

This skill is the complete working guide for the `routed_sessions` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_sessions`
- **Directory:** `packages/routed_sessions`
- **Version in this checkout:** `0.2.0`
- **Role:** Session stores, middleware, and context helpers
- **Purpose:** The Routed adapter for server_sessions. It binds SessionStore behavior to EngineContext, cookies, session middleware, and a typed provider.

### Public API

- `RoutedSessionsProvider(SessionConfig(store: ...))` installs the session runtime.
- `sessionMiddleware(store)` loads and commits sessions around the request.
- `ctx.session`, `ctx.getSession`, `ctx.setSession`, `ctx.clearSession`, and `ctx.sessionId` are the request-facing context helpers.
- The barrel re-exports server_sessions contracts such as Session, SessionStore, CookieStore, and MemoryStore.
- `SessionConfig` controls the adapter’s framework-facing configuration.

### Public imports

- `package:routed_sessions/routed_sessions.dart`

### Runtime package dependencies

- `routed_core`
- `server_contracts`
- `server_sessions`

### Composition rules

- Construct MemorySessionStore, CookieStore, or another server_sessions store and pass it to both provider/middleware as required by the composition.
- Use the same session configuration and cookie policy in production and routed_testing.
- Keep session serialization, storage, locking, and expiry behavior in server_sessions.

### Known hazards

- Ensure middleware runs before handlers that read/write session state and commits after the response.
- Do not expose session identifiers or cookie secrets in logs.
- Test missing/expired sessions, clear behavior, concurrent updates, cookie attributes, and response commit failures.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_sessions/server_sessions.dart';

final store = MemorySessionStore();
final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedSessionsProvider(SessionConfig(store: store)),
]);
engine.use(sessionMiddleware(store));
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_sessions`.
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

Cover provider config, context helpers, middleware load/commit, session store boundaries, cookie handling, expiry, and review-fix regressions.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_sessions
dart analyze --fatal-infos packages/routed_sessions
dart test packages/routed_sessions/test
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
