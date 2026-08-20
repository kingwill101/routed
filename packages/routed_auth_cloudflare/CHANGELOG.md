## 0.1.0

- Add a typed Cloudflare D1 `AuthStore` with prefix-isolated, idempotent
  migrations.
- Cover every required public store-conformance case plus concurrent session,
  JWT, device-authorization, and email-OTP mutations.
- Add an optional live Worker harness while keeping JavaScript interop and
  `package:web` behind `routed_node`.
- Fail closed for callback-spanning account deletion until D1 can provide the
  required cross-plugin transaction boundary.
