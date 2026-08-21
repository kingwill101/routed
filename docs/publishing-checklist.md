# Routed Ecosystem Publishing Checklist

This checklist captures the steps we followed to validate that the core packages are ready for pub.dev and the order to release them.

## Active pre-auth release snapshot

The isolated release is being published from
`release/publish-pre-auth-2026-08-20`, based on the recovery anchor
`release/pre-auth-2026-08-18` at `f665d2eb` (`chore: prepare packages for
release`). The publish branch currently ends at `6b6caba9` and contains only
release metadata fixes; the auth-era `master` work is not part of this
snapshot.

Uploaded from this snapshot so far:

- `routed_sessions` `0.2.0`
- `routed_storage` `0.2.0`
- `routed_views` `0.2.0`
- `routed_cache` `0.2.0`
- `routed_auth` `0.2.0`
- `routed_hotwire` `0.1.6`
- `routed_observability` `0.1.0`
- `routed_rate_limit` `0.1.0`
- `routed_security` `0.1.0`
- `routed_validation` `0.1.0`
- `routed_openapi` `0.1.0`
- `routed_openapi_builder` `0.1.0`
- `routed` `0.5.0`
- `routed_cli` `0.3.0`

All publishable packages selected for this pre-auth snapshot are now uploaded
and visible on pub.dev. The `server_*` versions used by this snapshot were
already hosted; `server_auth` `0.2.0` belongs to the separate auth-era release
line.

## Pre-flight
- [ ] Ensure the workspace is on a clean commit (no modified or untracked files).
- [ ] Verify `resolution: workspace` remains in each package so local development keeps working.
- [ ] Update package versions, dependency constraints, README, LICENSE, and CHANGELOG entries as needed.

### Compare local and published versions

Run the workspace audit before choosing release versions:

```bash
dart run tool/pub_release_audit.dart
```

The report compares each package's local `pubspec.yaml` version with the
latest pub.dev release and shows whether its changelog starts with
`Unreleased`. Use `--json` for automation and `--check` to fail when a package
already published at that version still needs a version decision.

Internal pre-1.0 dependencies use explicit ranges such as
`>=0.4.0 <1.0.0`. This keeps applications compatible with future `0.x` minor
releases while preserving `1.0.0` as the next deliberate breaking boundary;
`<=1.0.0` is not used because it would admit that boundary.

### Current hosted-release status

The following snapshot was refreshed from the workspace audit and package
publish dry-runs on 2026-08-21 after the recent publish run. Keep this list
updated after each successful publish.

Packages that are still drifted from current pub.dev and still require action:

- No publishable package is currently behind the hosted release recorded by
  the latest audit. `routed_hotwire` was corrected to `0.1.6` and published
  after the earlier `0.1.4`/`0.1.5` entries.

`server_native` is intentionally excluded from this release even though its
current version is already published; native assets require a separate
artifact and metadata release.

Packages whose publishable contents still match their current pub.dev release
and do not need a release in this batch:

- `routed_analyzer` `0.1.0`
- `routed_http` `0.1.0`
- `routed_logging` `0.2.0`
- `routed_testing` `0.4.0`
- `server_cache` `0.2.0`
- `server_contracts` `0.1.0`
- `server_rate_limit` `0.1.0`
- `server_sessions` `0.1.0`
- `server_storage` `0.1.0`

`routed_io` currently differs only in tests, development metadata, ignore rules,
and its changelog. Leave it out unless those non-library changes are
intentionally released.

The dependency graph has no workspace cycles. The release audit checked 28
publishable packages after excluding `server_native`, with satisfiable local
constraints. The listed batch is ready for a dry-run cycle.

The auth implementation roadmap is tracked in
[`docs/auth-worklist.md`](auth-worklist.md).

## Validation Commands
For each package below, run the validation commands from the package directory:

```bash
dart pub get
dart pub publish --dry-run
```

Local packages include the extracted `routed_*` and `server_*` packages. Each
must be published before a package that declares it as a hosted dependency.
The external prerequisites (`server_testing`, `server_testing_shelf`, and
`property_testing`) are published separately. Filtering the audit's
dependency order to only non-same status packages gives:

No package is currently required by the audit's same-status release filter.

`server_native` is intentionally excluded from this release. Its native
version, generated metadata, GitHub release assets, and artifact hashes will
be handled in a separate native release.

## Publish Order

When you are ready to publish for real, use the numbered order above. A
dry-run can be performed without publishing anything by running this from the
workspace root:

```bash
for package in \
  packages/routed_hotwire; do
  (cd "$package" && dart pub publish --dry-run) || {
    result=$?
    # Pub uses exit 65 for validation warnings (for example, a dirty tree).
    # Continue through those warnings but stop on resolver or archive errors.
    [ "$result" -eq 65 ] || exit "$result"
  }
done
```

Publish each package from its directory with:

```bash
dart pub publish
```

## Post-publish
- [ ] Tag the repository with the released versions.
- [ ] Push commits and tags.
- [ ] Update any release notes or documentation referencing the new versions.
