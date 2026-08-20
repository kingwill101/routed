---
name: routed-auth
description: Maintain, extend, document, test, or troubleshoot the routed_auth subsystem in the Routed Dart monorepo. Use when a task touches routed_auth APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_auth

This skill is the complete working guide for the `routed_auth` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_auth`
- **Directory:** `packages/routed_auth`
- **Version in this checkout:** `0.2.0`
- **Role:** Routed auth plugin mounting, typed deployment binding, and runtime conformance support
- **Purpose:** Routed HTTP, session, and router integration on top of server_auth. It supplies auth routes, middleware, runtime wiring, and a typed auth store boundary.

### Public API

- `AuthServiceProvider` creates and exposes the `AuthRuntime` through `AuthManager`.
- `AuthOptions<EngineContext>` carries the typed `AuthStore`, provider list, and feature modules.
- `AuthRoutes` owns auth route wiring; `requireAuthenticated()` supplies the session guard middleware.
- `SessionAuth`, `jwtAuthentication`, and `oauth2Introspection` provide Routed middleware wrappers.
- `Haigate`, `GatePayloadProvider`, and `GateDeniedHandler` bridge authorization gates into the Routed middleware pipeline.
- The barrel re-exports server_auth contracts and the auth crypto helpers; persistence is supplied by the application.

### Public imports

- `package:routed_auth/routed_auth.dart`
- `package:routed_auth/testing.dart`

### Runtime package dependencies

- `routed_core`
- `routed_http`
- `routed_sessions`
- `routed_views`
- `server_auth`
- `server_sessions`

### Composition rules

- Batteries-included apps register the Routed provider catalogue, then provide `AuthOptions` with an explicit `AuthStore`.
- Slim apps add `AuthServiceProvider()` after `Engine.defaultProviders` and register the same typed options.
- Use routed_sessions when session-backed authentication needs the session adapter; use server_auth directly for framework-neutral auth runtime work.

### Known hazards

- Do not create a persistence store implicitly; `AuthServiceProvider` must use the application-supplied store.
- Do not add a second provider registry or untyped provider configuration.
- Test unauthenticated, authenticated, invalid-token, callback, and session-update paths whenever middleware or provider wiring changes.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:server_auth/server_auth.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  AuthServiceProvider(),
]);
engine.instance<AuthOptions<EngineContext>>(
  AuthOptions(store: InMemoryAuthStore(), providers: const []),
);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_auth`.
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

Cover provider initialization, route registration, guard behavior, JWT/OAuth wrappers, callback events, session updates, and property-based auth flows.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_auth
dart analyze --fatal-infos packages/routed_auth
dart test packages/routed_auth/test
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
