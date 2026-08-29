# routed_node sample API

Small JSON API that demonstrates **`package:routed_node`**: Routed handlers on
the portable edge, served by Node, Bun, and Fetch-compatible hosts when
compiled for JavaScript.

```
example/api/
├── lib/app.dart          # routes + in-memory store
├── bin/server.dart       # serveNode entry (Node host)
├── bin/smoke.dart        # same routes via handlePortable (Dart VM)
├── package.json
├── test/                  # VM + Node/Bun integration tests
└── tool/build.sh         # legacy Node-only helper
```

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Service info |
| `GET` | `/health` | Liveness + capability snapshot |
| `GET` | `/api/items` | List items |
| `GET` | `/api/items/:id` | Get one item |
| `POST` | `/api/items` | Create (`{"name":"…","qty":1}`) |
| `DELETE` | `/api/items/:id` | Delete |
| `GET` | `/capabilities` | Runtime capability matrix |
| `GET` | `/stream` | Progressive response / flush |
| `POST` | `/echo` | Request body and header echo |
| `GET` | `/bindings/d1` | Live D1 write/read check |
| `GET` | `/bindings/durable-object` | Live SQLite Durable Object check |
| `GET` | `/bindings/r2` | Fixed-key native R2 binding check |
| `GET` | `/storage/r2` | Fixed-key `storage_fs` R2 check |
| `GET` | `/storage/r2/signed-url` | Mint a five-minute URL for the fixed private fixture |
| `GET` | `/storage/r2/files/readme.txt` | Download the fixture with a valid signed query |

Seed data: items `1` (alpha) and `2` (beta).

The sample intentionally exercises Routed's portable contracts: routing,
parameters, query strings, JSON input/output, status codes, multi-value
headers, streamed output, response flushing, lifecycle-safe initialization,
and runtime capability reporting.

## Quick check (Dart VM — no Node)

Exercises the **same** `createSampleEngine` routes through
`Engine.handlePortable` (no sockets). The sample is a monorepo workspace
package (`resolution: workspace`); run `dart pub get` from the repo root
or this directory.

```bash
cd packages/routed_node/example/api
dart pub get
dart run bin/smoke.dart
# or: npm run smoke
```

Example output:

```text
GET / → 200 {"service":"routed_node_api_sample",…}
GET /health → 200 {"ok":true,…}
GET /api/items → 200 {"items":[…]}
…
smoke ok
```

## Test on Node and Bun

The platform integration tests use the real host listener and native `fetch`:

```bash
dart test -p node test/node_integration_test.dart

dart compile js tool/bun_integration.dart -o /tmp/routed-bun.js -O2
bun /tmp/routed-bun.js
```

Node's raw HTTP upgrade path and Bun's native `server.upgrade` path are both
covered by the WebSocket echo integration. Deno uses the native
`Deno.upgradeWebSocket` bridge; a live Deno runtime check is still pending.

## Deploy to Cloudflare

From this project, the Routed CLI performs dependency setup, Dart JS
compilation, Fetch bootstrap generation, Wrangler configuration, and upload:

```bash
routed deploy --target cloudflare --name routed-api-demo
```

To deploy the binding-enabled sample, create a D1 database and pass its name
and ID together with the Durable Object class:

```bash
routed deploy --target cloudflare --name routed-bindings-demo \
  --cloudflare-factory environment \
  --d1 DB=DATABASE_NAME:DATABASE_ID \
  --r2 FILES=BUCKET_NAME \
  --durable-object COUNTER=Counter

npx wrangler secret put STORAGE_SIGNING_KEY --name routed-bindings-demo
```

The environment-aware factory registers `FILES` as an application-scoped R2
filesystem. `GET /storage/r2` exercises it through `ctx.storage('r2')`; the
existing `GET /bindings/r2` route demonstrates the lower-level binding API.
Both smoke routes use fixed keys so request input cannot overwrite or delete
unrelated objects. `GET /storage/r2/signed-url` seeds one fixed private fixture
and returns a five-minute capability URL for
`GET /storage/r2/files/readme.txt`. Direct, expired, or tampered requests are
rejected before R2 is read. A real application must authenticate and authorize
the exact object before issuing a URL; the public mint route exists only to
make this fixed demo fixture easy to validate.

The D1 smoke route expects this table in the remote database:

```sql
CREATE TABLE IF NOT EXISTS routed_live_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  marker TEXT NOT NULL
);
```

Use `--dry-run` to compile and validate without uploading. Authentication is
handled by Wrangler (`wrangler login` or `CLOUDFLARE_API_TOKEN`). No Worker entrypoint, shell script, or hand-written `wrangler.jsonc` is required.

### Live Cloudflare binding smoke test

The repository includes a disposable end-to-end smoke harness. It creates
temporary D1, R2, Queue, and Secrets Store resources; deploys service and
Workflow fixtures; deploys this sample through the Routed CLI; checks the live
binding routes; and removes everything when it finishes:

```bash
dart run tool/cloudflare_live_smoke.dart --deploy
```

Add `--containers` to attempt the Container check. Cloudflare Containers must
be enabled on a Workers Paid account; otherwise that check is reported as
skipped while the other bindings are still tested. Use `--keep` only while
debugging a live deployment.

## Deploy to Netlify

Netlify Edge Functions use the same Fetch bridge for HTTP and streaming
responses:

```bash
routed deploy --target netlify --name routed-api-netlify
```

Use `--dry-run` to compile and validate without uploading. Netlify requires
authentication for Edge Functions; use `netlify login` or set
`NETLIFY_AUTH_TOKEN`. The CLI generates the Edge Function wrapper and keeps it
under `.dart_tool/routed/deploy/netlify`.

Netlify does not provide a server-side WebSocket upgrade boundary inside Edge
Functions, so this deployment reports `webSocket: false`. For persistent
real-time connections, use a managed service such as Ably or deploy the
WebSocket route to Node.js or Cloudflare Workers.

## Run on Node.js

Target entry is `bin/server.dart` → [serveNode].

```bash
cd packages/routed_node/example/api
dart pub get
npm run build    # dart compile js bin/server.dart -o build/server.js
npm start        # node build/server.js
```

Env:

| Variable | Default | Meaning |
|----------|---------|---------|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8080` | Bind port |

```bash
HOST=127.0.0.1 PORT=3000 npm start
curl -s http://127.0.0.1:3000/health | jq .
curl -s http://127.0.0.1:3000/api/items | jq .
curl -s -X POST http://127.0.0.1:3000/api/items \
  -H 'content-type: application/json' \
  -d '{"name":"delta","qty":2}' | jq .
```

### Verified path (Node)

```bash
npm run build && npm start
# other terminal:
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/api/items
curl -s -X POST http://127.0.0.1:8080/api/items \
  -H 'content-type: application/json' -d '{"name":"delta","qty":2}'
```

The example targets **Node ≥ 22**, which provides
`process.getBuiltinModule('node:http')`; no JavaScript bootstrap file is needed.

Do **not** keep the process alive with huge `Duration`s — JS timers overflow
32-bit ms; the sample uses an open [Completer] instead.

### Smoke without Node

If you only want handler checks:

```bash
dart run bin/smoke.dart
```

## How it wires to Node

```text
Node http.IncomingMessage / ServerResponse
        │
        ▼
portableRequestFromNode / writePortableResponseToNode
        │
        ▼
Engine.handlePortable  (same as smoke.dart)
        │
        ▼
your routes in lib/app.dart
```

`serveNode` binds `node:http` and calls `dispatchNodeExchange` per request.

## Related

- Package README: [`../../README.md`](../../README.md)
- Portable host design: [`../../../../docs/portable-host-architecture.md`](../../../../docs/portable-host-architecture.md)
