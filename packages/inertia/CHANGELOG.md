## 0.1.2

- Fixed case-sensitive header lookups -- `InertiaHeaderUtils` now performs
  case-insensitive matching via a new `_get()` helper, fixing compatibility
  with `dart:io` `HttpHeaders` which lowercases header names.
- Added `extractHttpHeaders()` and `escapeInertiaHtml()` as public top-level
  functions in the `dart:io` helpers module.
- CLI scaffolding no longer hangs -- all package managers now pass
  `--no-interactive` (and `--yes` for npm) to `create-vite`.
- CLI `runInertiaCommand()` accepts an optional `environment` map forwarded
  to the spawned process.
- Updated `InertiaViteAssets` defaults to match Vite 7 conventions:
  `manifestPath` defaults to `client/dist/.vite/manifest.json`, `hotFile` to
  `client/public/hot`, and `entry` examples use `index.html` instead of
  `src/main.jsx`.

## 0.1.1

- Updated docs/examples/tests to import `package:inertia_dart/inertia_dart.dart`.
- Removed the legacy `inertia.dart` shim entrypoint.

## 0.1.0

- Initial public release of the Inertia Dart server package.
- Includes middleware, history flags, SSR helpers, asset tools, and CLI scaffolding.
