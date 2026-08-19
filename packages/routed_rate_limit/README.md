# routed_rate_limit
Routed adapter for `server_rate_limit`. The provider registers a
`RateLimitService` in the engine container; middleware evaluates the current
request and returns `429 Too Many Requests` with a `Retry-After` header when a
configured policy blocks it.

## Install

```yaml
dependencies:
  routed_core: ^0.4.0
  routed_rate_limit: ^0.1.0
  server_rate_limit: ^0.1.0
```

## Initialize and use

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

Future<void> main() async {
  final service = RateLimitService(const []);
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedRateLimitProvider(RateLimitConfig(service: service)),
    ],
  );

  engine.get(
    '/limited',
    (ctx) => ctx.json({'allowed': true}),
    middlewares: [rateLimitMiddleware(service)],
  );

  await engine.serve(port: 8080);
}

```

In a batteries-included app, call `registerRoutedProviders()` after importing
`package:routed/routed.dart` so `routed.rate_limit` is included. Use
`RoutedRateLimitProvider` explicitly when composing a slim `routed_core` engine.

To apply the same policies to `routed_auth`, pass the adapter to
`AuthOptions.rateLimiter`:

```dart
final service = RateLimitService(authPolicies);
final authOptions = AuthOptions<EngineContext>(
  providers: providers,
  store: authStore,
  rateLimiter: RoutedAuthRateLimiter(service),
);
```

The adapter evaluates the current request using the existing path, method,
and key resolver configuration. It does not expose auth secrets to the rate
limiter; configure trusted proxy ranges before using IP-based policies.
