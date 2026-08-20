## 0.1.0

- Add exact owner-checked OAuth account unlinking by provider ID and provider
  account ID. D1 binds an authoritative topology backed by its own users,
  credentials, accounts, and email-OTP stores, rechecks a usable fallback in
  the conditional delete statement, and records mixed external-store
  topologies as non-authoritative. Those applications still boot and use their
  plugins, while destructive unlink fails closed until every store can join.
- Add a data-preserving D1 migration and guarded issuance-lease transitions
  for device authorization. Lease acquisition, matching completion, and
  matching release use atomic D1 batches/statements and persist only digests,
  timestamps, and status metadata.
- Add a typed Cloudflare D1 `AuthStore` with prefix-isolated, idempotent
  migrations.
- Cover every required public store-conformance case plus concurrent session,
  JWT, device-authorization, and email-OTP mutations.
- Make session-token rotation contention-safe so one old token cannot produce
  multiple surviving replacement sessions.
- Add an optional live Worker harness while keeping JavaScript interop and
  `package:web` behind `routed_node`. A deployed remote-D1 run remains
  outstanding; local conformance tests do not claim live Cloudflare validation.
- Add an explicitly gated live-D1 conformance CLI with disposable-resource
  ownership checks, exact cleanup, external-database no-delete mode, secret
  redaction, bounded safe retries, and local control-plane tests. No live run is
  claimed until the CLI is invoked against Cloudflare.
- Add a D1-owned hard-deletion coordinator that validates immutable plugin
  plans before mutation and executes guarded plugin, core, token-consumption,
  deletion-receipt, and user deletion statements in one atomic batch. Core D1
  cleanup removes device authorization and email-OTP state even after those
  plugins are removed; unsupported active plugin adapters fail closed.
- Add an explicitly opt-in deployed Worker auth harness for the public session,
  JWT, plugin, external-provider, and browser-shaped WebAuthn contracts. The
  typed CLI is inert without `--run`, reads its token only from an environment
  variable, and calls only an already-deployed HTTPS Worker; it never invokes
  Cloudflare control-plane APIs or mutates account resources.
