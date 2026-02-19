# framework_suite

Standalone example project under `packages/server_native/example/` that pulls in all framework dependencies discussed for transport comparisons.

## Included dependencies

- `server_native` (path dependency to this repo package)
- `routed` (path dependency)
- `routed_io` (path dependency)
- `shelf`
- `relic`

## Usage

```bash
cd packages/server_native/example/framework_suite
dart pub get
dart run bin/main.dart
```

Use this project as a base for side-by-side framework experiments and benchmarks.
