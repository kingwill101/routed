# server_rate_limit
Framework-agnostic rate-limit policies and service runtime.

## Using with Routed

This package supplies `RateLimitService` and policies only. It does not
initialize an `Engine` provider. Use `routed_rate_limit` to add
`RoutedRateLimitProvider` and `rateLimitMiddleware` to a Routed app, or import
the batteries-included `routed` facade.
