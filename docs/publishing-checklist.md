# Routed Ecosystem Publishing Checklist

This checklist captures the steps we followed to validate that the core packages are ready for pub.dev and the order to release them.

## Pre-flight
- [ ] Ensure the workspace is on a clean commit (no modified or untracked files).
- [ ] Verify `resolution: workspace` remains in each package so local development keeps working.
- [ ] Update package versions, dependency constraints, README, LICENSE, and CHANGELOG entries as needed.

## Validation Commands
For each package below, run the validation commands from the package directory:

```bash
dart pub get
dart pub publish --dry-run
```

Local packages include the extracted `routed_*` and `server_*` packages. Each
must be published before a package that declares it as a hosted dependency.
The current package graph is intentionally released in dependency order:

1. External prerequisites: `server_testing`, `server_testing_shelf`, and
   `property_testing`.
2. Foundational local packages: `server_contracts`, `server_auth`,
   `server_cache`, `server_rate_limit`, `server_sessions`, `server_storage`,
   `server_native`, and `routed_core`.
3. `routed_testing` (it depends on `routed_core` and `server_testing`, but no
   longer depends on the `routed` facade).
4. The extracted `routed_*` feature packages.
5. `routed` (the batteries-included facade).
6. `routed_cli`.

## Publish Order
When you are ready to publish for real, follow the dependency-aware order:
1. External prerequisites and foundational local packages.
2. `routed_testing`.
3. Extracted `routed_*` feature packages.
4. `routed`.
5. `routed_cli`.

Publish each package from its directory with:

```bash
dart pub publish
```

## Post-publish
- [ ] Tag the repository with the released versions.
- [ ] Push commits and tags.
- [ ] Update any release notes or documentation referencing the new versions.
