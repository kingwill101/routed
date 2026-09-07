# Tenant, principal, and gate architecture

This example composes the normal server-side pieces together:

- `SessionAuth` hydrates an authenticated `AuthPrincipal`.
- `OrganizationPlugin` owns tenant membership and revalidates it for every
  request.
- `Haigate.organizationContext` resolves the explicit tenant from
  `X-Organization-Id` (or `organizationId`) and fails closed for non-members.
- Every SQL query includes `tenant_id`; `ctx.db()` is still the
  `routed_database` abstraction.
- `Haigate.middleware(['projects.create'])` demonstrates a tenant permission
  gate, while `ownsOrCanInOrganization` demonstrates owner-or-permission
  authorization for deletion.

The auth and organization stores are deliberately in-memory fixtures so the
example stays runnable. Replace them with durable `server_auth` stores for a
real deployment; the routing and database boundaries stay the same.

There are no generated models or `build_runner` steps. The provider runs the
Ormed migration before the engine accepts requests.

```bash
dart run bin/server.dart

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
