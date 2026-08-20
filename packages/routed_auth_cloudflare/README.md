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

Managed SCIM is an independently selected server plugin. Its D1 store is
obtained from the same opened adapter, so connection management, bearer
resolution, replay metadata, and coordinated user deletion share one durable
transaction domain:

```dart
final store = await authStore(env);
final scimConnections = AuthScimConnectionPlugin<MyRequestContext>(
  store: store.scimConnectionStore,
  authorize: (request) async {
    final user = request.invocation.user;
    if (user == null) return null;
    final access = await loadDirectoryAccess(
      request.invocation.context,
      request.organizationId,
    );
    if (access == null) return null;
    return AuthScimConnectionManagementPrincipal(
      tenantId: access.tenantId,
      organizationId: access.organizationId,
      subjectId: user.id,
    );
  },
);

final options = AuthOptions<MyRequestContext>(
  store: store,
  plugins: [scimConnections],
);
```

Only bearer digests and safe credential metadata are stored. Connection
creation, issuance, and rotation write their replay identity in the same D1
batch, so a committed retry returns metadata without reconstructing the raw
secret. The default replay lifetime is one day and can be changed with the
typed `scimReplayTtl` argument to `CloudflareD1AuthStore.open`.

The local tests run `AuthStoreConformanceSuite` and
`verifyOAuthAuthorizationCodeExchangeStoreConformance` against a deterministic
SQLite-backed implementation of the public `CloudflareD1Database` API. They
also inject a mid-batch fault and prove that code consumption and token
persistence roll back together. The separate

The root adapter implements `AuthUsernameStore`: normalized username
registration and rename commit the user projection and password credential in
one D1 batch, and contention relies on D1 uniqueness constraints. Safe username
removal rechecks every supported fallback inside that same store-owned batch
and fails closed for mixed or unsupported authentication-method stores.

The local tests also run `verifyAuthUsernameStoreConformance` against that
deterministic public D1 fake. The separate
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
including OAuth authorization-code and token records. It accepts only
backend-bound typed mutation plans it can compile into that batch; supported
authentication-method removal uses those plans, while mixed external stores
fail closed instead of advertising a false transaction guarantee.
