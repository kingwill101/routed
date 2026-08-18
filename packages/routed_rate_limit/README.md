# routed_rate_limit
Routed adapter for `server_rate_limit`. The provider registers a
`RateLimitService` in the engine container; middleware makes a chosen service
available to request handlers.

## Install

```yaml
dependencies:
  routed_core: ^0.3.3
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
      RoutedRateLimitProvider(service),
    ],
  );

  engine.get(
    '/limited',
    (ctx) async {
      final outcome = await ctx.checkRateLimit(
        _Request('GET', '/limited'),
      );
      return ctx.json({'allowed': outcome?.allowed ?? true});
    },
    middlewares: [rateLimitMiddleware(service)],
  );

  await engine.serve(port: 8080);
}

final class _Request implements RateLimitRequest {
  _Request(this.method, this.path);
  @override final String method;
  @override final String path;
  @override String get clientIP => '127.0.0.1';
  @override String get remoteAddr => '127.0.0.1';
  @override String header(String name) => '';
}
```

In a batteries-included app, call `registerRoutedProviders()` after importing
`package:routed/routed.dart` so `routed.rate_limit` is included. Use
`RoutedRateLimitProvider` explicitly when composing a slim `routed_core` engine.
