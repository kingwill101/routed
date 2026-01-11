## 0.3.0

## 0.2.1+1

- `routed` introduces a full auth stack (providers, callbacks/events, RBAC,
  policies, and session/JWT refresh) with expanded docs and examples.
- `server_testing` refreshes browser/driver bootstrapping, CLI ergonomics, and
  mocks `requestedUri` so auth redirect tests accept absolute callback URLs.
- `server_testing_shelf` updates Shelf translation behavior and aligns
  dependencies with the latest transport APIs.
- `routed_testing`, `property_testing`, and `routed_hotwire` refresh docs and
  metadata, with routed_hotwire modularizing the todo example.

## 0.2.1

- Added badges, funding links, and richer documentation for `property_testing`,
  `routed_testing`, `server_testing_shelf`, and `routed_cli`.

## 0.2.0

- `routed` adds a full localization stack, deep-merge config snapshots, logging
  tweaks, and richer lifecycle events (404 + WebSocket) that publish through
  `SignalHub`.
- `server_testing` ships contextual browser logging, binary overrides, exposed
  browser utilities, and new property coverage for the bootstrapper.
- `server_testing_shelf` now streams Shelf responses without double-closing and
  includes property-based adapter tests with shared test config.
- `routed_testing` gains property tests that verify route parameters across
  transports and tidies the request handler bootstrap.
- `property_testing` updates `StatefulPropertyRunner` generics so custom command
  objects keep full type information.
- `routed_cli` rebuilds the config generator on Routed’s snapshots, improves
  provider manifest handling, and refreshes the project templates (new env vars,
  dependencies, and typed server entrypoints).

## 1.0.0

- Initial version.
