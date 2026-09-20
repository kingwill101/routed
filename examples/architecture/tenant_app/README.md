# Tenant, principal, and gate architecture

This example composes the normal server-side pieces together:

- `SessionAuth` hydrates an authenticated `AuthPrincipal`.
- `OrganizationPlugin` owns tenant membership and revalidates it for every
  request.
- `Haigate.organizationContext` resolves the explicit tenant from
  `X-Organization-Id` (or `organizationId`) and fails closed for non-members.
- Every project query is built through `ctx.db().table(...)`, includes
  `tenant_id`, and stays behind the `routed_database` abstraction.
- `Haigate.middleware(['projects.create'])` demonstrates a tenant permission
  gate, while `ownsOrCanInOrganization` demonstrates owner-or-permission
  authorization for deletion.

Both organization data and core auth data are durable: `server_auth_ormed`
owns the Ormed migration entries and stores users, password credentials,
sessions, provider accounts, and auth challenges in the same SQLite database.
The example reopens that database on restart and can still sign Alice in.
Remember-me tokens are hashed and persisted in the same Ormed records table,
so opting into remember-me flows does not introduce process-local state.

There are no generated models or `build_runner` steps. The provider runs the
Ormed migration before the engine accepts requests.

```bash
dart run bin/server.dart

# The default is the file-backed storage/tenant.sqlite. Set DATABASE_PATH to
# retain organizations at another location between restarts.
mkdir -p storage
DATABASE_PATH=storage/tenant.sqlite dart run bin/server.dart

# Alice signs in (save the session cookie).
curl -i -c alice.cookies -X POST http://127.0.0.1:8081/auth/signin/credentials \
  -H 'content-type: application/json' \
  -d '{"email":"alice@example.com","password":"password123"}'

# The principal is available through SessionAuth.current(ctx).
curl -b alice.cookies http://127.0.0.1:8081/api/me

# Alice can read and create only in Acme.
curl -b alice.cookies -H 'X-Organization-Id: tenant-acme' \
  http://127.0.0.1:8081/api/projects
curl -b alice.cookies -H 'X-Organization-Id: tenant-acme' \
  -H 'content-type: application/json' -X POST \
  -d '{"name":"new Acme project"}' \
  http://127.0.0.1:8081/api/projects

# Membership is checked before the database query; this returns 403 and never
# exposes Beta's rows.
curl -i -b alice.cookies -H 'X-Organization-Id: tenant-beta' \
  http://127.0.0.1:8081/api/projects
```
