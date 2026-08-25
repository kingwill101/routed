# server_rate_limit

Framework-agnostic rate-limit policies, algorithms, and service runtime.

`server_rate_limit` is the low-level package. It does not know about a web
framework, create a repository, or choose a response format. Adapt your
framework request to `RateLimitRequest`, provide a `Repository`, and decide how
to turn a blocked `RateLimitOutcome` into a response.

## Basic setup

Compile declarative policies once at application startup and reuse the
resulting service for incoming requests:

```dart
import 'package:server_rate_limit/server_rate_limit.dart';

final backend = CacheRateLimiterBackend(repository: appRepository);

final policies = compileRateLimitPolicies(
  specs: [
    const RateLimitPolicySpec(
      name: 'public-api',
      match: '/api/**',
      method: 'GET',
      strategy: RateLimitStrategy.tokenBucket,
      capacity: 60,
      interval: Duration(minutes: 1),
      window: Duration.zero,
      period: Duration.zero,
      burstMultiplier: 1.0,
      key: RateLimitKeySpec.ip(),
      failover: RateLimitFailoverMode.block,
    ),
  ],
  backend: backend,
  defaultFailover: RateLimitFailoverMode.block,
);

final service = RateLimitService(policies);

// `request` is an adapter implementing RateLimitRequest.
final blocked = await service.check(request);
if (blocked != null) {
  // Return 429 and use blocked.retryAfter for a Retry-After header.
}
```

The selected strategy uses only its corresponding timing fields:

- `tokenBucket` uses `capacity`, `interval`, and `burstMultiplier`.
- `slidingWindow` uses `capacity` and `window`.
- `quota` uses `capacity` and `period`.

`CacheRateLimiterBackend` persists state through the supplied
`server_contracts` `Repository`. For atomic read-modify-write updates across
requests or hosts, the repository's store must implement `LockProvider`.
Without that capability, use the backend only where occasional concurrent
updates are acceptable or provide a backend with stronger atomic guarantees.

## Backend failures

Set `failover` per policy, or use `defaultFailover` when a policy omits it:

- `allow` fails open and permits the request without the distributed limit.
- `block` fails closed and rejects the request for a short retry interval.
- `local` uses process-local state and therefore does not enforce one shared
  quota across hosts or isolates.

Choose deliberately for the operation being protected. Authentication and
credential endpoints commonly fail closed; availability-sensitive public
endpoints may prefer fail-open behavior.

## Using with Routed

This package supplies `RateLimitService` and policies only. It does not
initialize an `Engine` provider. Use `routed_rate_limit` to add
`RoutedRateLimitProvider` and `rateLimitMiddleware` to a Routed app, or import
the batteries-included `routed` facade.
