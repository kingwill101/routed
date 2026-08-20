## 0.1.0

- Implement `AuthAnonymousAccountMutationStore` on the root D1 adapter. Create,
  delete, and upgrade mutations now use backend transactions and fail closed
  without any process-local fallback.
- Add append-only schema migration version 7 for transient creation guards and
  bounded digest-only operation receipts. Generic and typed hard deletion scrub
  subject receipts in the same rollback boundary; retained completion receipts
  never store an `AuthUser` payload.
- Run the public anonymous-store conformance suite against the local D1 fake,
  including contention, replay mismatch, target binding, hard-deletion scrub,
  and injected rollback coverage. Add the non-fault cases to the opt-in live D1
  executor without running or creating live Cloudflare resources.
- Add a plugin-scoped D1 managed-SCIM connection store with exact tenant and
  organization lookup, digest-only bearer credentials, database-constrained
  issuance replay identity, atomic rotation and disablement, and typed replay
  lifetime configuration.
- Add schema migration version 6 for SCIM connections, credentials, and replay
  metadata. Foreign-key cascades join direct subject/tenant cleanup and guarded
  user deletion to the same D1 transaction domain.
- Decode Cloudflare REST D1 metadata using the current boolean
  `served_by_primary` contract and cover the browser-shaped response in the
  live-control-plane adapter tests.
- Run the public managed-SCIM adapter conformance suite locally and from the
  opt-in live-D1 executor, with property, contention, digest-persistence, and
  injected rollback tests. No deployed D1 run is claimed by this release.
- Add prefix-isolated D1 OAuth client, authorization-code, access-token, and
  refresh-token persistence with digest-only secrets and credentials.
- Add a backend-native atomic authorization-code exchange that revalidates all
  bindings, persists the prepared token digest, and consumes the code in one D1
  batch. Public conformance, contention, PKCE, injected rollback, refresh-token
  rotation, topology, migration, and deletion coverage are included.
- Reject in-memory, foreign-database, and otherwise split provider-mode stores
  whenever the host auth store is durable; there is no durable fallback bridge.
- Implement the root `AuthUsernameStore` capability with atomic D1 batches for
  normalized registration, rename, and supported safe removal. Add public
  username adapter conformance, contention, rollback injection, replay, and
  hard-deletion coverage; mixed authentication-method stores fail closed.
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
