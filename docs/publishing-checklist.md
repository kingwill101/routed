# Routed Ecosystem Publishing Checklist

This checklist captures the steps we followed to validate that the core packages are ready for pub.dev and the order to release them.

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
publish dry-runs on 2026-08-20. Keep this list updated after each successful
publish.

Packages with no release currently visible on pub.dev:

- `routed_auth`
- `routed_auth_cloudflare`
- `routed_cache`
- `routed_observability`
- `routed_openapi`
- `routed_openapi_builder`
- `routed_rate_limit`
- `routed_security`
- `routed_sessions`
- `routed_storage`
- `routed_validation`
- `routed_views`

Packages previously published, but whose current local version is still
pending publication:

- `routed` `0.5.0` (pub.dev: `0.3.3`)
- `routed_cli` `0.3.0` (pub.dev: `0.2.1+1`)
- `routed_core` `0.5.0` (pub.dev: `0.4.0`)
- `routed_hotwire` `0.1.4` (pub.dev: `0.1.2`)
- `routed_node` `0.2.0` (pub.dev: `0.1.0`)
- `server_auth` `0.2.0` (pub.dev: `0.1.0`)

`server_native` is intentionally excluded from this release even though its
current version is already published; native assets require a separate
artifact and metadata release.

Packages whose publishable contents still match their current pub.dev release
and do not need a release in this batch:

- `routed_analyzer` `0.1.0`
- `routed_http` `0.1.0`
- `routed_logging` `0.2.0`
- `routed_testing` `0.4.0`
- `server_cache` `0.1.0`
- `server_contracts` `0.1.0`
- `server_rate_limit` `0.1.0`
- `server_sessions` `0.1.0`
- `server_storage` `0.1.0`

`routed_io` currently differs only in tests, development metadata, ignore
rules, and its changelog. Leave it out unless those non-library changes are
intentionally released.

The dependency graph has no workspace cycles. The release audit checked 28
publishable packages after excluding `server_native`, with satisfiable local
constraints. After adding the documented `false_secrets` entry for the
test-only OAuth key fixture, `server_auth 0.2.0` also passes its publish
dry-run.

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
`property_testing`) are published separately. The local packages are ordered
as follows:

1. `server_contracts`
2. `server_auth`, `server_cache`, `server_sessions`, `server_storage`
3. `server_rate_limit` (after `server_cache`)
4. `routed_core` (after `server_contracts`)
5. `routed_testing` (after `routed_core` and external `server_testing`)
6. `routed_analyzer`, `routed_io`, `routed_node`, `routed_http`,
   `routed_logging`, `routed_security`, and `routed_observability`
7. `routed_rate_limit`, `routed_sessions`, `routed_storage`, and
   `routed_validation`
8. `routed_views` and `routed_cache`
9. `routed_auth` (after `server_auth`, `routed_sessions`, `routed_views`,
   and `routed_http`)
10. `routed_openapi`
11. `routed_openapi_builder`
12. `routed_hotwire`
13. `routed` (the batteries-included facade)
14. `routed_cli`

`server_native` is intentionally excluded from this release. Its native
version, generated metadata, GitHub release assets, and artifact hashes will
be handled in a separate native release.

## Publish Order

When you are ready to publish for real, use the numbered order above. A
dry-run can be performed without publishing anything by running this from the
workspace root:

```bash
for package in \
  packages/server_contracts \
  packages/server_auth \
  packages/server_cache \
  packages/server_sessions \
  packages/server_storage \
  packages/server_rate_limit \
  packages/routed_core \
  packages/server_testing/routed_testing \
  packages/routed_analyzer \
  packages/routed_io \
  packages/routed_node \
  packages/routed_http \
  packages/routed_logging \
  packages/routed_security \
  packages/routed_observability \
  packages/routed_rate_limit \
  packages/routed_sessions \
  packages/routed_storage \
  packages/routed_validation \
  packages/routed_views \
  packages/routed_cache \
  packages/routed_auth \
  packages/routed_openapi \
  packages/routed_openapi_builder \
  packages/routed_hotwire \
  packages/routed \
  packages/routed_cli; do
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
