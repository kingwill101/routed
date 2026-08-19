## Unreleased

- **Breaking security change:** proxy support requires explicit trusted proxy
  networks and no longer trusts all forwarded addresses by default.

## 0.5.0

- **Breaking:** Consolidate provider and registry imports on
  `package:routed/routed.dart` and `package:routed_core/routed_core.dart`;
  remove the redundant `routed_core/providers.dart` sub-barrel.

## 0.4.0

- Split the batteries-included facade across independently publishable
  `routed_*` feature packages.
- Registered the official feature providers through the public `routed`
  facade while keeping slim applications on `routed_core`.
- Updated the package graph and documentation for the current provider APIs.

## 0.1.0
- Initial bundle (PR L) - re-exports routed + server_* + routed_auth
