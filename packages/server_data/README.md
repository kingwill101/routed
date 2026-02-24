# server_data

Framework-agnostic runtime data capabilities:
- cache implementations
- storage implementations
- session store implementations
- rate limit core implementations

`server_data` contains reusable runtime implementations that do not depend on a
specific web framework. Framework packages can compose these primitives and add
their own request/response wiring.

## Installation

```yaml
dependencies:
  server_data: ^0.1.0
```

## Entry points

- `package:server_data/cache.dart`
- `package:server_data/storage.dart`
- `package:server_data/sessions.dart`
- `package:server_data/rate_limit.dart`
- `package:server_data/server_data.dart` (umbrella export)

## Package Selection

- Use `server_data` for concrete runtime implementations.
- Use `server_contracts` if you only need interfaces/contracts.
- Use framework adapters (`routed`, `shelf_*`, etc.) only for request/response wiring.

## Cache example

`DataCacheManager` is the framework-agnostic cache lifecycle core.

```dart
import 'package:server_data/server_data.dart';

final cache = DataCacheManager(prefix: 'demo:')
  ..registerStore('default', {'driver': 'array'});

final repo = cache.store('default');
await repo.put('status', 'ok', const Duration(seconds: 30));
print(await repo.get('status')); // ok
```

## Storage example

```dart
import 'package:server_data/server_data.dart';

final storage = StorageManager()
  ..registerDisk('local', LocalStorageDisk(root: 'storage/app'))
  ..setDefault('local');

final path = storage.resolve('avatars/user.png');
print(path);
```

## Session store example

```dart
import 'dart:io';

import 'package:server_data/server_data.dart';

class RequestStub implements SessionRequest {
  RequestStub({List<Cookie>? cookies}) : cookies = cookies ?? <Cookie>[];
  @override
  final List<Cookie> cookies;
  @override
  String header(String name) => '';
}

class ResponseStub implements SessionResponse {
  final List<Cookie> cookies = <Cookie>[];
  @override
  void setCookie(String name, dynamic value, {int? maxAge, String path = '/', String domain = '', bool secure = false, bool httpOnly = false, SameSite? sameSite}) {
    cookies.add(Cookie(name, value.toString()));
  }
}

final store = MemorySessionStore(
  codecs: [SecureCookie(key: SecureCookie.generateKey())],
  defaultOptions: SessionOptions(maxAge: 120),
);

final response = ResponseStub();
final session = Session(name: 'app', options: SessionOptions(maxAge: 120));
session.setValue('user_id', '42');
await store.write(RequestStub(), response, session);
```

## Rate limit example

```dart
import 'package:server_data/server_data.dart';

final repo = RepositoryImpl(ArrayStore(), 'rate_limit', '');
final backend = CacheRateLimiterBackend(repository: repo);
final policy = CompiledRateLimitPolicy(
  name: 'api',
  matcher: RequestMatcher(method: 'GET', pattern: '/api/**'),
  keyResolver: const IpKeyResolver(),
  algorithm: buildBucketConfig(
    capacity: 2,
    refillInterval: const Duration(seconds: 30),
  ),
  backend: backend,
  failover: RateLimitFailoverMode.local,
);
final service = RateLimitService([policy]);
```

## Full runnable example

```bash
dart run example/main.dart
```

See `example/main.dart` for combined cache, storage, session, and rate-limit usage.
See `example/README.md` for run instructions and expected output.

## Migration Notes

If older code imported cache/storage/session runtime types from
`package:routed/routed.dart`, prefer importing directly from `server_data`
entrypoints for framework-agnostic usage.

## Framework integration pattern

`server_data` stays framework-agnostic by taking small request/response
contracts. Your adapter package should map framework objects into those
contracts at the boundary.

```dart
class AdapterRateLimitRequest implements RateLimitRequest {
  AdapterRateLimitRequest({
    required this.method,
    required this.path,
    required this.clientIP,
    required this.headers,
  });

  @override
  final String method;

  @override
  final String path;

  @override
  final String clientIP;

  final Map<String, String> headers;

  @override
  String get remoteAddr => clientIP;

  @override
  String header(String name) => headers[name.toLowerCase()] ?? '';
}
```

Keep this mapping layer thin. Business/runtime behavior should remain inside
`server_data` services and stores.

## Validation

```bash
dart analyze
dart test
dart run example/main.dart
```

## License

MIT
