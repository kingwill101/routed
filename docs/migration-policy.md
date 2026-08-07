# Migration Policy — Routed Modular Packages

## Compat Exports
- `routed` keeps re-exporting `routed_*` public APIs for one minor version after split.
- Direct imports `import 'package:routed_*/...'` and `import 'package:server_*/...'` are canonical.

## Deprecation Period
- Deprecated `routed` re-exports emit `dart analyze` `deprecated_member_use` info for 1 minor version, then removed in next major.

## Warning Format
- `// deprecated: use routed_foo instead` with `deprecated` annotation and `dart doc` note.
- CI fails on `dart analyze --fatal-infos` if deprecated usage outside `routed` itself.

## Workspace + CI
- `pubspec.yaml` workspace lists all `packages/*` split packages.
- CI: `dart analyze --fatal-infos`, `dart test --coverage`, `dart run coverage:format_coverage --lcov -i coverage -o coverage/lcov.info`
