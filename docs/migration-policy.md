# Migration Policy — Routed Modular Packages

- Apps depend on **`package:routed`** (batteries).
- Adapters and portable code depend on **`package:routed_core`** / **`server_*`**.
- There is no compatibility alias package; import the canonical package names directly.
- See [migration-split-packages.md](./migration-split-packages.md) and [package-boundary-contract.md](./package-boundary-contract.md).
