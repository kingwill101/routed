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

Packages:
1. `packages/server_testing/server_testing`
2. `packages/server_testing/server_testing_shelf`
3. `packages/routed`
4. `packages/server_testing/routed_testing`
5. `packages/property_testing`
6. `packages/routed_cli`

## Publish Order
When you are ready to publish for real, follow the dependency-aware order:
1. `server_testing`
2. `server_testing_shelf`
3. `routed`
4. `routed_testing`
5. `property_testing`
6. `routed_cli`

Publish each package from its directory with:

```bash
dart pub publish
```

## Post-publish
- [ ] Tag the repository with the released versions.
- [ ] Push commits and tags.
- [ ] Update any release notes or documentation referencing the new versions.
