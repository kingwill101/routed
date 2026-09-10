# Routed Cloudflare Queue and Scheduler example

This example validates the Cloudflare Worker event surface end to end:

- `POST /dispatch?value=hello` publishes a codegen-free `routed_jobs` message.
- Cloudflare delivers the message to the Worker `queue()` handler.
- `processCloudflareJobBatch` runs the job and acknowledges terminal results.
- The job stores its result in a KV namespace.
- A one-minute Cron Trigger wakes Routed's scheduler.
- The scheduler evaluates a five-minute application frequency, claims the
  occurrence in a Durable Object-backed ledger, and dispatches the same job
  through the queue.

The Dart application never imports `dart:io`, `package:web`, or Cloudflare's
JavaScript types. `worker_wrapper.mjs` is only the module-worker boundary that
forwards `fetch`, `queue`, and `scheduled` events to the typed Routed exports.
Cloudflare's one-minute cron is a platform wake-up; the application frequency
is defined in Dart and is not duplicated in `wrangler.jsonc`.

## Local build

From the repository root:

```bash
dart pub get
cd examples/cloudflare_jobs
dart compile js bin/worker.dart -o build/worker.dart.js -O2
npx wrangler@latest dev --config wrangler.jsonc
curl http://localhost:8787/health
curl -X POST 'http://localhost:8787/dispatch?value=local'
curl http://localhost:8787/result
curl 'http://localhost:8787/cdn-cgi/local/scheduled'
```

Local Wrangler provides the scheduled test endpoint. Queue delivery can be
validated against a live queue, or by using the live deployment flow below.

## Live Cloudflare validation

Authenticate Wrangler once:

```bash
npx wrangler@latest login
```

Create a new KV namespace and copy its ID into `wrangler.jsonc`:

```bash
npx wrangler@latest kv namespace create RESULTS
```

Create the producer/consumer queue (the dead-letter queue is created by the
consumer configuration when the Worker is deployed):

```bash
npx wrangler@latest queues create routed-cloudflare-jobs-example
```

Build and deploy:

```bash
dart pub get
dart compile js bin/worker.dart -o build/worker.dart.js -O2
npx wrangler@latest deploy --config wrangler.jsonc
```

Use the `workers.dev` URL printed by Wrangler:

```bash
curl "$WORKER_URL/health"
curl -X POST "$WORKER_URL/dispatch?value=live"
for attempt in $(seq 1 12); do
  result=$(curl -fsS "$WORKER_URL/result")
  echo "$result"
  case "$result" in
    *'"processed":{'*) break ;;
  esac
  sleep 5
done
```

The first response proves the HTTP Worker and queue metrics binding. The
second proves the Routed producer. The result response proves the queue
consumer executed the job and wrote KV. For the scheduled path, either wait
for the one-minute wake-up and five-minute application frequency or run the
local scheduled endpoint; Cloudflare Cron Trigger changes can take several
minutes to propagate.

Cloudflare Queues are at-least-once. Jobs must therefore be idempotent; this
example writes by job ID as well as to `last` so duplicate delivery is visible
without corrupting state. The queue has a dead-letter queue configured for
messages that exhaust Cloudflare's retry budget.
