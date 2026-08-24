## Unreleased

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.

## 0.1.0

- **Breaking security change:** `TrustedProxyConfig(enabled: true)` now
  requires an explicit non-empty proxy network list; it no longer defaults to
  trusting every address.
- Use routed core's host-neutral IP/CIDR matching for IP filters so security
  rules remain usable on worker runtimes.
- Initial package scaffold for the routed modular package split.
