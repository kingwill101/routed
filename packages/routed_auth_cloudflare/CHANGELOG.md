## 0.1.1

- Keep WebAuthn counter validation within JavaScript's exact integer range so
  D1-backed auth Workers compile and preserve the unsigned 32-bit contract.

## 0.1.0

- Make the SQL-backed `CloudflareD1AuthStore` extensible so the Dart IO
  `routed_auth_sqlite` adapter can reuse its typed persistence implementation
  without duplicating auth lifecycle behavior.
- Support historical user-data namespaces in the D1 deletion coordinator so
  `AuthOptions.historicalUserDataNamespaces` fails hard deletion closed when a
  removed plugin contributor is absent.
- Add a typed `historicalAuthenticationMethodNamespaces` inventory for D1
  deployments. Safe authentication-method removal now fails closed when a
  previously deployed external plugin namespace is absent from active
  authoritative contributors.
- Run the deployed Worker auth conformance harness against a temporary
  Cloudflare Worker. Session, JWT, plugin, external-provider, and
  browser-shaped WebAuthn suites passed; the Worker and secret were deleted
  afterward. Isolate sequential suite requests from reused edge connections.
- Validate the live disposable-D1 harness through migrations v9, v10, and v11.
  API-key rotation/capacity, WebAuthn challenge/counter, phone issuance and
  deletion, username, OAuth exchange, rollback, and prefix-isolation cases all
  passed against Cloudflare D1, and the owned database was deleted afterward.
- Add append-only migration version 11 and a typed root-owned D1 phone-number
  backend. Challenges, verified identities, and issuance receipts are bounded;
  code and operation identifiers persist only as digests.
- Add atomic phone issue/verify commands with replay binding, contention-safe
  lockout, user creation/projection, hard-deletion cleanup, local adapter
  conformance, capacity, rollback, and secret-inspection coverage. Wire the
  non-fault phone cases into the opt-in live-D1 harness.
- Add backend-owned safe phone-identity removal. D1 rechecks the composed
  fallback inventory in one batch, clears the verified projection and phone
  artifacts, and lets phone authentication preserve safe removal of other
  primary methods. No HTTP authorization policy is implied by this storage
  capability.
- Add append-only migration version 10 and typed root-owned D1 WebAuthn
  challenge and authenticator stores. Challenges are bounded and digest-only;
  credential IDs are unique and counters use compare-and-set updates.
- Add exact same-domain passkey removal, backend-owned hard-deletion cleanup
  that survives plugin removal, deletion receipts against user-ID reuse, and
  bounded public-key and metadata validation. Mixed stores fail closed.
- Run reusable WebAuthn conformance, 200 hostile-input property cases,
  capacity, secret-inspection, contention, rollback, and deletion tests against
  the local D1 fake. Non-fault cases are wired into the offline/live harness.
- Add append-only migration version 9 and a typed `store.apiKeys` D1 adapter.
  API-key issue, lookup, touch, revoke, rotate, list, expiry pruning, and
  user-access revocation persist only secret digests and bounded safe metadata.
- Enforce `apiKeyMaxRecords` during issue and rotation, including replacement
  at capacity, with deterministic contention and full D1-batch rollback after
  a replacement insert.
- Add a backend-bound API-key hard-deletion plan and exact opt-in primary-key
  revocation for authoritative D1 topologies. Mixed or foreign stores fail
  closed without a process-local fallback. Root deletion also scrubs the
  backend-owned table after plugin removal.
- Run the public API-key adapter conformance suite, hostile-identifier
  properties, digest inspection, migration/drop-all, deletion, topology, and
  fault tests against the local D1 fake. Non-fault cases are wired into the
  opt-in live harness.
- Implement `AuthAnonymousAccountMutationStore` on the root D1 adapter. Create,
  delete, and upgrade mutations now use backend transactions and fail closed
  without any process-local fallback.
- Add append-only schema migration version 7 for transient creation guards and
  bounded digest-only operation receipts. Generic and typed hard deletion scrub
  subject receipts in the same rollback boundary; retained completion receipts
  never store an `AuthUser` payload.
- Run the public anonymous-store conformance suite against the local D1 fake,
  including contention, replay mismatch, target binding, hard-deletion scrub,
  and injected rollback coverage. A disposable live D1 run also passed the six
  non-fault anonymous cases together with the existing core, SCIM, username,
  OAuth-exchange, rollback, and prefix-isolation cases; the owned database was
  independently confirmed deleted afterward.
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
  injected rollback tests. The non-fault SCIM cases passed the disposable live
  D1 run described above.
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
- Add D1-backed typed magic-link and email-OTP command transactions, a
  digest-only magic-link migration, exactly-one-winner adapter conformance, and
  per-statement rollback fault coverage for consume-plus-user transitions.
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
  `package:web` behind `routed_node`. Local conformance tests remain separate
  from the explicitly authorized deployed Worker run.
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
