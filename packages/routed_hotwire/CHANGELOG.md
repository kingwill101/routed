## 0.1.7 - 2026-08-25

- Completed public API documentation and adopted the `very_good_analysis`
  lint baseline.

## 0.1.6

- Release metadata housekeeping: republish to restore publish-order consistency.

## 0.1.4

- Updated dependency constraints for the typed core and feature adapter
  release.
- Updated Turbo request and response helpers and examples for the current
  Routed context APIs.
- Refreshed the integration dependencies and browser-test coverage.

## 0.1.2

- Fixed "Cannot modify unmodifiable map" error in `_attachLoggingContext` when
  accessing `ctx.turbo` - now properly creates and stores logger instances.

## 0.1.1

- Synced routed ecosystem dependency constraints.

## 0.1.0

- First release containing Turbo request helpers, response builders, stream
  utilities, and WebSocket broadcasting adapters for the routed framework.
- Modularized the Hotwire todo example and refreshed docs/config to match the
  latest workspace conventions.
