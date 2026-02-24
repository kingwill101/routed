## 1. Pubspec Updates
- [ ] 1.1 Remove workspace-only fields (`publish_to`, `resolution`) and add repository metadata for each target package.
- [x] 1.2 Replace path/implicit workspace cross-dependencies with version constraints that reflect the coordinated release (e.g., `^0.1.0`).

## 2. Validation
- [ ] 2.1 Run `dart pub get` and `dart pub publish --dry-run` for `server_contracts`, `server_data`, `server_auth`, `server_testing`, `server_testing_shelf`, `routed`, `routed_testing`, and `property_testing` to confirm publish readiness.

## 3. Documentation
- [x] 3.1 Capture the publishing checklist (order, commands, tagging expectations) in the repo so future releases follow the same process.
