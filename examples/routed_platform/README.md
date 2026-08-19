# Routed Platform Example

This is the executable reference architecture for a Routed application that
owns a small control plane and delegates work to a Stem worker.

It is intentionally process-local: platform metadata is held in memory and
Stem uses its in-memory broker and result backend. The HTTP API, typed provider
configuration, idempotency behavior, authentication boundary, worker startup,
and shutdown lifecycle are still real.

The project follows the `routed_cli` application shape: `lib/config.dart`
owns typed provider wiring, `lib/app.dart` owns routes, and `lib/commands.dart`
adds project commands.

```bash
dart pub get
dart run routed_cli:routed platform:e2e
dart run routed_cli:routed routes
dart test
```

The example is a reference for composition and consumer safety. It is not a
durable production gateway: restarting the process loses tenants, idempotency
records, task metadata, and results. A durable adapter can later replace the
in-memory platform store while preserving the same route and provider seams.
