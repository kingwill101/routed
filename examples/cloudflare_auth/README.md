# Cloudflare D1 auth example

This is a runnable Routed application for Cloudflare Workers. It uses:

- `CloudflareD1AuthStore` for durable auth data and migrations in D1
- encrypted, signed server sessions in an HttpOnly cookie
- the built-in credentials provider and `/auth` routes
- a protected `/account` route
- typed Worker bindings, without `package:web` or JS interop in application code

The same application composition is tested on Dart IO with
`SqliteAuthStore`, which implements the D1 adapter contract. That catches
route, session, and database wiring errors before deployment.

## Prerequisites

- Dart 3.9 or newer
- Node.js and `npx`
- a Cloudflare account with Wrangler authenticated (`npx wrangler login`)
- a Workers-compatible D1 database

## Deploy

From this directory, create a D1 database and copy the returned values into
`wrangler.jsonc`:

```bash
cd examples/cloudflare_auth
npx wrangler d1 create routed-cloudflare-auth-example
```

Set `AUTH_ORIGIN` to the exact HTTPS origin that will serve the Worker. Then
create the session secret. It must be a base64-encoded value containing at
least 32 random bytes:

```bash
SESSION_KEY="base64:$(openssl rand -base64 64 | tr -d '\n')"
printf '%s\n' "$SESSION_KEY" | npx wrangler secret put SESSION_KEY
```

Build the Dart Worker and deploy the JavaScript wrapper:

```bash
mkdir -p build
dart pub get
dart compile js bin/worker.dart -O2 -o build/worker.dart.js
npx wrangler deploy
```

`CloudflareD1AuthStore.open` applies the current typed schema migrations on
the first Worker initialization. No handwritten SQL migration file is
required for the auth tables.

## Try the app

```bash
export ORIGIN='https://your-worker.your-subdomain.workers.dev'

curl -s "$ORIGIN/health" | jq .
curl -s "$ORIGIN/auth/providers" | jq .

curl -s -c cookies.txt "$ORIGIN/auth/csrf" | tee csrf.json | jq .
CSRF=$(jq -r .csrfToken csrf.json)

curl -s -b cookies.txt -c cookies.txt \
  -H 'content-type: application/json' \
  -H "origin: $ORIGIN" \
  -X POST "$ORIGIN/auth/register/credentials" \
  -d "{\"email\":\"worker@example.test\",\"password\":\"a deliberately long password\",\"_csrf\":\"$CSRF\"}" | jq .

curl -s -b cookies.txt "$ORIGIN/account" | jq .
curl -s -b cookies.txt -X POST "$ORIGIN/auth/signout" | jq .
```

The credentials route returns a session cookie. The `/account` request proves
that the session was resolved from that cookie and the user was read back
from D1.

## Local verification

The local test uses SQLite only as a D1-compatible test double. It does not
change the Worker code path or the public Cloudflare API:

```bash
dart test
dart analyze
```

To verify that the actual Worker entrypoint compiles through the JavaScript
interop path:

```bash
mkdir -p build
dart compile js bin/worker.dart -O2 -o build/worker.dart.js
```

The example intentionally wires an explicit, currently empty
`RateLimitService`. The repository does not yet ship a durable Cloudflare
rate-limit backend, so do not expose this example to untrusted public traffic
without adding one and configuring policies for the auth routes.
