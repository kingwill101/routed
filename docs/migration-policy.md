# Migration Policy — Routed Modular Packages

## Compat Exports
- Feature APIs are **not** re-exported from `routed`. Import owning packages (`routed_*` / `server_*`) or use `routed_full`.
- Migration path: change `package:routed/...` feature imports to the owning package; keep `package:routed/routed.dart` for Engine/Context/Router only.

## Deprecation Period
- Deprecated `routed` re-exports emit `dart analyze` `deprecated_member_use` info for 1 minor version, then removed in next major.

## Warning Format
- `// deprecated: use routed_foo instead` with `deprecated` annotation and `dart doc` note.
- CI fails on `dart analyze --fatal-infos` if deprecated usage outside `routed` itself.

## Workspace + CI
- `pubspec.yaml` workspace lists all `packages/*` split packages.
- CI: `dart analyze --fatal-infos`, `dart test --coverage`, `dart run coverage:format_coverage --lcov -i coverage -o coverage/lcov.info`

## App migration
- See [migration-split-packages.md](./migration-split-packages.md) for import and provider migration steps.
