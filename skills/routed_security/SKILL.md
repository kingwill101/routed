---
name: routed-security
description: Maintain, extend, document, test, or troubleshoot the routed_security subsystem in the Routed Dart monorepo. Use when a task touches routed_security APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_security

This skill is the complete working guide for the `routed_security` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_security`
- **Directory:** `packages/routed_security`
- **Version in this checkout:** `0.1.0`
- **Role:** CORS middleware plus IP filtering, network matching, and trusted-proxy primitives
- **Purpose:** Security providers and primitives for CORS, IP filtering, network matching, trusted proxies, and request-size policy. Security headers and CSRF remain explicit application/middleware concerns.

### Public API

- `RoutedSecurityProvider` consumes `RoutedSecurityConfig` and validates all policy values before boot.
- `CorsConfig`, `TrustedProxyConfig`, and `IpFilterConfig` configure the provider.
- `IpFilter` and `IpFilterAction` implement allow/deny decisions; `NetworkMatcher` and `TrustedProxyResolver` provide reusable primitives.
- CORS handles allowed-origin headers and OPTIONS preflight; maxRequestSize enforces request-size policy.
- `registerRoutedSecurityProviders()` registers the provider catalogue when composing this package directly.

### Public imports

- `package:routed_security/routed_security.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- Use explicit origins, methods, and headers for credentialed CORS; do not use wildcard origins with credentials.
- Enable trusted proxies only for known proxy networks and use the resolver before trusting forwarded client IPs.
- Use primitives directly when no provider is needed; configuration is typed and fixed for the engine lifetime.

### Known hazards

- Never treat an arbitrary forwarded address as the client IP without trusted-proxy validation.
- Do not claim this package supplies CSRF or all security headers; those remain explicit concerns.
- Test preflight, denied origin, allow/deny IP boundaries, proxy chains, oversized bodies, and invalid CIDR/header values.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_security/routed_security.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedSecurityProvider(RoutedSecurityConfig(
    cors: CorsConfig(enabled: true, allowedOrigins: ['https://app.example']),
    trustedProxies: TrustedProxyConfig(enabled: true, proxies: ['10.0.0.0/8']),
  )),
]);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_security`.
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

Cover config validation, CORS headers/preflight, IP filter actions, network matching, trusted proxy resolution, request-size rejection, and provider boot failures.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_security
dart analyze --fatal-infos packages/routed_security
dart test packages/routed_security/test
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
