# routed_node sample API

Small JSON API that demonstrates **`package:routed_node`**: Routed handlers on
the portable edge, served with Node’s `http` module when compiled for JS.

```
example/api/
├── lib/app.dart          # routes + in-memory store
├── bin/server.dart       # serveNode entry (Node host)
├── bin/smoke.dart        # same routes via handlePortable (Dart VM)
├── package.json
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

## Deploy to Cloudflare

From this project, the Routed CLI performs dependency setup, Dart JS
compilation, Fetch bootstrap generation, Wrangler configuration, and upload:

```bash
routed deploy --target cloudflare --name routed-api-demo
```

Use `--dry-run` to compile and validate without uploading. Authentication is
handled by Wrangler (`wrangler login` or `CLOUDFLARE_API_TOKEN`). No Worker entrypoint, shell script, or hand-written `wrangler.jsonc` is required.

## Deploy to Netlify

Netlify Edge Functions use the same Fetch bridge:

```bash
routed deploy --target netlify --name routed-api-netlify
```

Use `--dry-run` to compile and validate without uploading. Netlify requires
authentication for Edge Functions; use `netlify login` or set
`NETLIFY_AUTH_TOKEN`. The CLI generates the Edge Function wrapper and keeps it
under `.dart_tool/routed/deploy/netlify`.

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
