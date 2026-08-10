# routed_cache

Routed adapter for [`server_cache`](https://github.com/kingwill101/routed/tree/master/packages/server_cache) — the framework-agnostic cache runtime (`DataCacheManager`, `Repository`, `Store`).

Wraps `server_cache` (array/file/redis/null stores, `DataCacheManager`, `Repository`) for `routed` `EngineContext` via `ContextCache` extension (`ctx.cache`/`getCache`/`removeCache`/`cacheForever`/`rememberCache*`/`incrementCache`/`decrementCache`) and `Store` middleware/provider.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_cache: ^0.1.0
  server_cache: ^0.1.0
```

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_cache/routed_cache.dart';
import 'package:server_cache/server_cache.dart';

void main() async {
  final cacheManager = DataCacheManager()
    ..registerStore('array', {'driver': 'array', 'serialize': false});

  final engine = Engine(
    options: [withCacheManager(cacheManager)],
  );

  engine.get('/', (ctx) async {
    await ctx.cache('greeting', 'hello', 60);
    final value = await ctx.getCache('greeting'); // pull semantics (get+delete)
    await ctx.cacheForever('forever', 'permanent');
    final remembered = await ctx.rememberCacheForever('once', () => 'computed');
    return ctx.json({'value': value, 'remembered': remembered});
  });

  // Store middleware (server_contracts Store) for hasCache/cacheStore
  engine.use(cacheMiddleware(MemoryStore()));

  await engine.serve();
}
```

See [`example/cache_example.dart`](example/cache_example.dart) for runnable example.

## Testing

```bash
dart test packages/routed_cache
dart analyze --fatal-infos packages/routed_cache/lib
```
