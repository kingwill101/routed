---
name: routed-cache
description: Maintain, extend, document, test, or troubleshoot the routed_cache subsystem in the Routed Dart monorepo. Use when a task touches routed_cache APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_cache

This skill is the complete working guide for the `routed_cache` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_cache`
- **Directory:** `packages/routed_cache`
- **Version in this checkout:** `0.2.0`
- **Role:** Cache services and context helpers for Routed
- **Purpose:** The Routed adapter for server_cache. It binds cache stores and DataCacheManager behavior to EngineContext, middleware, events, and a typed provider.

### Public API

- `RoutedCacheProvider(CacheConfig(store: ...))` installs the cache store in the engine.
- `withCacheManager(DataCacheManager)` supplies the manager option used by the context extension.
- `ctx.cache`, `ctx.getCache`, `ctx.removeCache`, `ctx.cacheForever`, `ctx.rememberCache*`, `ctx.incrementCache`, and `ctx.decrementCache` are the request-facing helpers.
- `cacheMiddleware(store)` exposes store-oriented helpers such as `ctx.cacheStore` and `ctx.hasCache`.
- The adapter re-exports server_cache stores, `DataCacheManager`, `Repository`, cache events, and `CacheConfig`.

### Public imports

- `package:routed_cache/routed_cache.dart`

### Runtime package dependencies

- `routed_core`
- `server_cache`
- `server_contracts`

### Composition rules

- Choose ArrayStore, FileStore, RedisStore, or NullStore in server_cache and pass the selected Store into the provider.
- Use the provider for the typed context service and middleware when handlers need store access.
- Keep cache algorithms and store implementations in server_cache; keep EngineContext integration here.

### Known hazards

- `getCache` has pull semantics in this adapter: it reads and deletes the value. Use a non-pull read API when the value must remain.
- Do not silently change serialization, TTL, tag, lock, or increment behavior inherited from server_cache.
- Test array/file/redis/null composition only where relevant, and always test expiry and missing-key behavior.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_cache/routed_cache.dart';
import 'package:server_cache/server_cache.dart';

final store = ArrayStore();
final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedCacheProvider(CacheConfig(store: store)),
]);
engine.use(cacheMiddleware(store));
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_cache`.
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

Cover context extensions, provider options, cache middleware, events, locks, tags, pull semantics, and store boundary behavior.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_cache
dart analyze --fatal-infos packages/routed_cache
dart test packages/routed_cache/test
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
