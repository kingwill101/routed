# server_contracts

Framework-agnostic contracts for server ecosystem packages.

`server_contracts` is the dependency boundary package for the server ecosystem.
It defines shared interfaces and value contracts used by runtime packages such
as `server_data`, `server_auth`, and framework adapters (for example, Routed or
Shelf integrations).

## Scope

This package intentionally contains only contract artifacts:

- abstract interfaces
- typedefs and callback signatures
- value contracts
- contract-level exceptions

This package must not contain concrete runtime implementations.

## Installation

```yaml
dependencies:
  server_contracts: ^0.1.0
```

## Exports

- `package:server_contracts/cache.dart`
  - `Store`, `Repository`, `Factory`, `Lock`, `LockProvider`
- `package:server_contracts/config.dart`
  - `Config`
- `package:server_contracts/translation.dart`
  - `TranslationLoader`, `TranslatorContract`

## Typical usage

Use `server_contracts` for framework-agnostic signatures and extension points.
Concrete runtime behavior should be implemented by other packages.

```dart
import 'package:server_contracts/server_contracts.dart';

Future<String> readHealth(Repository repository) async {
  final value = await repository.get('health');
  return value?.toString() ?? 'unknown';
}
```

## Package Selection

- Use `server_contracts` when you need interfaces only.
- Use `server_data` when you need concrete cache/storage/session/rate-limit implementations.
- Use `server_auth` when you need auth providers, JWT, callbacks, and authorization primitives.

## Migration Notes

If older code imported these contracts from `package:routed/routed.dart`,
switch to direct imports from `server_contracts` to avoid framework coupling.

## Contract implementation example

Runnable example:

```bash
dart run example/main.dart
```

See `example/main.dart` for:

- a minimal `Config` implementation
- an in-memory `Store` and `Repository`
- a lightweight `TranslatorContract` implementation

## Design rules

- Keep contracts small and stable.
- Do not import framework runtimes here.
- Move concrete behavior to dedicated runtime packages.
