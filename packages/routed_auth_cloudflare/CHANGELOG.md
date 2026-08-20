## 0.1.0

- Add a typed Cloudflare D1 `AuthStore` with prefix-isolated, idempotent
  migrations.
- Cover every required public store-conformance case plus concurrent session,
  JWT, device-authorization, and email-OTP mutations.
- Make session-token rotation contention-safe so one old token cannot produce
  multiple surviving replacement sessions.
- Add an optional live Worker harness while keeping JavaScript interop and
  `package:web` behind `routed_node`. A deployed remote-D1 run remains
  outstanding; local conformance tests do not claim live Cloudflare validation.
- Fail closed for callback-spanning account deletion until D1 can provide the
  required cross-plugin transaction boundary.
