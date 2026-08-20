# routed_auth_cloudflare

Durable Cloudflare D1 persistence for `package:server_auth`. The package is a
small host adapter: `server_auth` remains framework-neutral, while this package
depends explicitly on `server_auth` and the host-neutral D1 types from
`routed_node`.

```dart
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';

Future<CloudflareD1AuthStore> authStore(CloudflareEnvironment env) {
  return CloudflareD1AuthStore.open(
    env.d1('AUTH_DB'),
    schema: const CloudflareD1AuthSchema(
      tablePrefix: 'my_app_auth',
    ),
  );
}
```

`CloudflareD1AuthStore.open` applies typed, idempotent migrations. There is no
YAML configuration and application code does not import `package:web` or use
`dart:js_interop`.

This adapter does not currently own the OAuth provider-mode authorization-code
or access-token tables, so it does not implement
`OAuthAuthorizationCodeExchangeStore`. Provider-mode code grants therefore
cannot be configured with D1 yet; use an adapter with an authoritative atomic
exchange implementation instead of composing independent D1 statements and
claiming transaction safety.

The local tests run `AuthStoreConformanceSuite` against a deterministic
SQLite-backed implementation of the public `CloudflareD1Database` API. The
separate [live harness](test/live/README.md) is intentionally not part of the
default test command and must be deployed to a real D1 database before it can
be claimed as live validation.

The independent
[deployed Worker auth harness](tool/deployed_worker/README.md) verifies Routed's
session, JWT, plugin, external-provider, and browser-shaped WebAuthn contracts
inside an already-deployed Cloudflare Worker. It is also opt-in and does not
create, update, or delete Cloudflare resources.

Cloudflare D1 exposes atomic statement batches, but not a transaction that can
span the arbitrary callback required by `AuthAccountDeletionStore`. The
adapter therefore fails closed by not advertising that optional capability;
the conformance case is reported as skipped. Core records are never partially
deleted under a false transaction guarantee. A future D1-specific typed
deletion-contributor protocol can safely turn contributor operations into one
batch.
