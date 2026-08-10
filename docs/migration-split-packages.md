# Migrating to modular packages

This guide covers moving apps from the monolithic `package:routed` import surface
to the slim foundation + `routed_*` / `server_*` packages.

## Package roles

| Package | Role |
|---------|------|
| `routed` | Slim core: `Engine`, `EngineContext`, `Request`, `Response`, `Router`, config, DI |
| `routed_*` | Framework adapters (middleware, providers, EngineContext extensions) |
| `server_*` | Portable runtimes (no `package:routed` in `lib/`) |
| `routed_logging` | Request logging provider and `RoutedLogger` |
| `routed_full` | Batteries barrel: re-exports official packages + registers providers |

## Import changes

**Before (monolith):**

```dart
import 'package:routed/routed.dart';
// sessions, cache, auth, views, static files all available
```

**After (selective):**

```dart
import 'package:routed/routed.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_views/routed_views.dart';
import 'package:routed_storage/routed_storage.dart'; // engine.static(...)
import 'package:routed_http/routed_http.dart';     // form/query/SSE
```

**After (batteries):**

```dart
import 'package:routed_full/routed_full.dart';
// officialProvidersRegistered is true after import
```

Foundation **does not** re-export feature APIs. Prefer direct package imports.

## Common symbol moves

| Old (via `routed`) | New package |
|--------------------|-------------|
| `sessionMiddleware`, session store types | `routed_sessions` / `server_sessions` |
| `FileHandler`, `Dir`, `engine.static` | `server_storage` / `routed_storage` |
| Auth guards, JWT/OAuth helpers | `routed_auth` / `server_auth` |
| Cache context / store | `routed_cache` / `server_cache` |
| Views / Liquid / localization | `routed_views` |
| Form/query/SSE helpers | `routed_http` |
| Observability provider | `routed_observability` |
| CLI | `routed_cli` (not `package:routed/console.dart`) |
| Analyzer plugin | `routed_analyzer` |

## Providers (`http.providers`)

Foundation registry ships only:

- `routed.core`
- `routed.routing`
- `routed.uploads`
- `routed.logging`

Import `package:routed_full/routed_full.dart` (or call the package
`register*Providers()` helpers) to add:

- `routed.auth`, `routed.logging`, `routed.views`, `routed.localization`
- `routed.observability`, `routed.cache`, `routed.sessions`, `routed.storage`
- `routed.rate_limit`

Default constructors use safe in-memory/local backends. Override with explicit
instances when you need redis/file drivers:

```dart
Engine(
  providers: [
    ...Engine.defaultProviders,
    RoutedCacheProvider(customStore), // optional override
  ],
);
```

## Config templates

Config YAML/JSON still uses **Liquid** via `package:liquify` (`{{ env.VAR }}`,
filters). View engines remain in `routed_views`.

## Checklist

1. Replace feature imports with owning packages (or `routed_full`).
2. Register / pass feature providers as above.
3. Run `dart analyze` and tests.
4. Drop unused heavy deps that only feature packages need.
