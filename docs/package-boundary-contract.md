# Package Boundary Contract — Routed Ecosystem

## Roles

| Package | Role |
|---------|------|
| **`routed_core`** | Slim foundation: `Engine`, `EngineContext`, `Request`, `Response`, `Router`, config, DI |
| **`routed`** | Batteries-included default for apps: re-exports core + official adapters/runtimes and registers providers |
| **`routed_*`** | Framework adapters on `routed_core` + `server_*` |
| **`server_*`** | Portable runtimes (no framework imports in `lib/`) |

## Dependency rules

```
app → package:routed
        ├─ routed_core
        ├─ routed_* adapters
        └─ server_* runtimes

adapter package → routed_core + server_*   (never depend on package:routed)
server_*        → no routed / routed_core
```

## Canonical imports

```dart
// Applications
import 'package:routed/routed.dart';

// Adapter authors / minimal surface
import 'package:routed_core/routed_core.dart';
import 'package:routed_core/providers.dart';
```

## Provider IDs

- Core registry defaults: `routed.core`, `routed.routing`, `routed.uploads`
- Registered when importing `package:routed`: auth, logging, views, localization, observability, cache, sessions, storage, rate_limit

## Verification

- Adapters depend only on `routed_core` (not batteries `routed`)
- `server_*` lib purity tests pass
- No circular deps
