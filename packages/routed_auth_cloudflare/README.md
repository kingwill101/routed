# routed_auth_cloudflare

Durable Cloudflare D1 persistence for `package:server_auth`. The package is a
small host adapter: `server_auth` remains framework-neutral, while this package
depends explicitly on `server_auth` and the host-neutral D1 types from
`routed_node`.

```dart
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/server_auth.dart';

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

Provider mode must use all three OAuth stores from the same opened adapter:

```dart
final store = await authStore(env);
final oauthProvider = OAuthProviderModePlugin<MyRequestContext>(
  clientStore: store.oauthClientStore,
  authorizationCodeExchangeStore:
      store.oauthAuthorizationCodeExchangeStore,
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [oauthProvider],
);
```

The adapter persists client-secret, authorization-code, access-token, and
refresh-token digests only. Authorization-code exchange uses one D1 atomic
batch to revalidate every binding, insert the prepared token-digest record,
and consume the code. A durable runtime rejects in-memory, foreign-database,
or otherwise split OAuth store topologies instead of falling back.

The local tests run `AuthStoreConformanceSuite` and
`verifyOAuthAuthorizationCodeExchangeStoreConformance` against a deterministic
SQLite-backed implementation of the public `CloudflareD1Database` API. They
also inject a mid-batch fault and prove that code consumption and token
persistence roll back together. The separate
[live harness](test/live/README.md) is intentionally not part of the default
test command and must be deployed to a real D1 database before it can be
claimed as live validation.

The independent
[deployed Worker auth harness](tool/deployed_worker/README.md) verifies Routed's
session, JWT, plugin, external-provider, and browser-shaped WebAuthn contracts
inside an already-deployed Cloudflare Worker. It is also opt-in and does not
create, update, or delete Cloudflare resources.

Cloudflare D1 exposes atomic statement batches, but not a transaction that can
span the arbitrary callback required by `AuthAccountDeletionStore`. The
adapter therefore fails closed by not advertising that optional capability;
the conformance case is reported as skipped. Core records are never partially
deleted under a false transaction guarantee. The separate typed user-deletion
coordinator does compose guarded plugin and core cleanup into one D1 batch,
including OAuth authorization-code and token records.
