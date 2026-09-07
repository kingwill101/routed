# {{{routed:humanName}}}

Cloudflare Workers starter for [Routed](https://kingwill101.github.io/routed/)
with typed D1 database migrations and Routed authentication.

## Deploy

Create a D1 database, then run the dry build first:

```bash
dart pub get
wrangler d1 create {{{routed:packageName}}}-db
wrangler secret put SESSION_KEY

routed deploy --target cloudflare \
  --cloudflare-factory environment \
  --d1 DB={DATABASE_NAME}:{DATABASE_ID} \
  --var AUTH_ORIGIN=https://{{{routed:packageName}}}.example.com \
  --name {{{routed:packageName}}} \
  --dry-run
```

When the dry build succeeds, remove `--dry-run` to upload the Worker. The
`--d1` option emits the Wrangler binding and the generated Worker receives it
through `CloudflareEnvironment`. `AUTH_ORIGIN` must be the exact HTTPS origin
used by browser clients. `SESSION_KEY` is read as a Wrangler secret and is
used to sign the HttpOnly session cookie.

## Application structure

- `lib/app.dart` exports `createCloudflareEngine`, the environment-backed
  Worker factory consumed by Routed's Cloudflare deploy flow.
- The VM-facing `createEngine` also includes `routedNodeCliProviders()`, so
  `routed deploy` is discovered from `routed_node`; the conditional provider
  is empty when this app is compiled for a Worker.
- `lib/database.dart` registers D1 with `RoutedDatabaseProvider` and defines a
  codegen-free Ormed migration.
- `lib/auth.dart` composes `routed_auth` with the D1-backed
  `CloudflareD1AuthStore`, credentials provider, and secure cookie sessions.
- `GET /db/health` checks the migration ledger through `ctx.db()`.
- The auth provider adds the standard `/auth/*` routes during provider boot.
- `bin/server.dart` is a direct Fetch-compatible Worker entrypoint for local
  compilation; normal deployments can use `routed deploy`.

Provider boot is awaited before the first request, so both the app migration
and auth schema are ready before the Worker serves traffic. Keep
`migrateOnBoot` disabled in a multi-owner production setup and run the same
migration list as a controlled release step. The generated
`AllowAllAuthRateLimiter` is intentionally explicit so the starter has no
hidden topology; replace it with a durable limiter before exposing auth
publicly.
