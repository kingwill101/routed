## 1. Pubspec Updates
- [x] 1.1 Ensure publish metadata and required package files (`repository`, `LICENSE`, `CHANGELOG`) are present for each target package while retaining monorepo workspace compatibility.
- [x] 1.2 Replace path/implicit workspace cross-dependencies with version constraints that reflect the coordinated release (e.g., `^0.1.0`).

## 2. Validation
- [x] 2.1 Run `dart pub get` and `dart pub publish --dry-run` for `server_contracts`, `server_data`, `server_auth`, `server_testing`, `server_testing_shelf`, `routed`, `routed_testing`, and `property_testing` to confirm publish readiness.

## 3. Documentation
- [x] 3.1 Capture the publishing checklist (order, commands, tagging expectations) in the repo so future releases follow the same process.
