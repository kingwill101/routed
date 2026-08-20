# Deployed Worker auth conformance

This opt-in harness verifies Routed auth inside an already-deployed Cloudflare
Worker. It exercises the public session, JWT, plugin, external-provider, and
browser-shaped WebAuthn conformance contracts with deterministic in-memory
fixtures.

It is not a production auth service. Use a short-lived test Worker with a
dedicated token. Neither the Worker nor the local runner calls Cloudflare's
control-plane APIs, and the runner never creates, updates, or deletes account
resources.

## Prepare the Worker

From `packages/routed_auth_cloudflare`, compile the Dart entrypoint:

```bash
dart compile js tool/deployed_worker/worker.dart \
  -o tool/deployed_worker/worker.dart.js -O2
```

The checked-in `worker_wrapper.mjs` exposes the generated Routed Fetch handler
as a module Worker. The checked-in `wrangler.jsonc` has an explicit
`compatibility_date`; review and deliberately advance that date when adopting
new runtime behavior.

Set a dedicated secret binding through your normal Cloudflare workflow. Do not
put the value in `wrangler.jsonc` or source control:

```bash
npx wrangler secret put ROUTED_AUTH_CONFORMANCE_TOKEN \
  --config tool/deployed_worker/wrangler.jsonc
npx wrangler deploy --config tool/deployed_worker/wrangler.jsonc
```

Those commands are user-invoked examples. Routed does not execute them as part
of tests, builds, or the local harness.

## Run selected suites

Make the Worker origin and the same dedicated token available to the local
runner, then opt in with `--run`:

```bash
export ROUTED_AUTH_WORKER_ORIGIN=https://your-worker.example.workers.dev
read -rs ROUTED_AUTH_CONFORMANCE_TOKEN
export ROUTED_AUTH_CONFORMANCE_TOKEN

dart run tool/deployed_worker_auth_conformance.dart --run \
  --suite session,jwt,plugins,external-providers,webauthn
```

Omit `--suite` to run every suite. The token cannot be passed as a command-line
argument and is never printed. Without `--run`, the command prints its usage
and makes no network request.

The runner calls only these token-protected endpoints on the configured HTTPS
origin:

- `GET /__routed_auth_conformance/health`
- `POST /__routed_auth_conformance/run`

Public failures contain stable case or error identifiers only. Detailed
exceptions, credentials, token values, provider fixtures, and stack traces are
not returned by the Worker or printed by the runner.
