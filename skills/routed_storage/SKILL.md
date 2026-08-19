---
name: routed-storage
description: Maintain, extend, document, test, or troubleshoot the routed_storage subsystem in the Routed Dart monorepo. Use when a task touches routed_storage APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_storage

This skill is the complete working guide for the `routed_storage` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_storage`
- **Directory:** `packages/routed_storage`
- **Version in this checkout:** `0.2.0`
- **Role:** Storage managers, disks, static-mount provider, middleware, and filesystem helpers
- **Purpose:** The Routed adapter for server_storage. It exposes StorageManager/disks through EngineContext and adds static-file middleware, file-serving extensions, and declarative static mounts.

### Public API

- `RoutedStorageProvider(StorageConfig(...))` binds the storage manager/disks to EngineContext.
- `StorageConfig`, `ctx.storageManager`, and `ctx.storageDisk` configure/access the runtime.
- `storageMiddleware(manager)` provides storage-oriented request helpers.
- `RoutedStaticProvider(StaticConfig(...))` registers declarative static mounts with route, disk, path, index, and list_directories options.
- `EngineStaticFiles`, `RouterStaticFiles`, and `FileHandlerEngineContext` provide file-serving helpers.
- The barrel re-exports server_storage StorageManager, StorageDisk, local/cloud disks, and static file contracts.

### Public imports

- `package:routed_storage/routed_storage.dart`

### Runtime package dependencies

- `routed_core`
- `server_storage`

### Composition rules

- Initialize and await the StorageManager before resolving it from the container; local disks can be configured by RoutedStorageProvider.
- Use a supplied StorageDisk for cloud storage; do not assume the provider can create cloud credentials/configuration by itself.
- Static mounts support GET/HEAD, index files, optional directory listings, route replacement on config reload, and traversal validation.

### Known hazards

- Validate traversal and mount paths before opening a file; never concatenate untrusted path segments without the storage boundary.
- Keep static route ownership in routed_storage, not in routed_core or generic feature adapters.
- Test missing files, HEAD parity, index/list behavior, traversal rejection, disk selection, and reload replacement.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:server_storage/server_storage.dart';

final manager = StorageManager()..registerDisk('local', LocalStorageDisk(root: 'storage/app'))..setDefault('local');
final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedStorageProvider(manager: manager),
  RoutedStaticProvider(StaticConfig(enabled: true, mounts: [
    StaticMountConfig(route: '/assets', disk: 'local'),
  ])),
]);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_storage`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a `lib/src` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

Cover manager initialization, local/cloud disk boundaries, static provider config, GET/HEAD serving, indexes/listings, traversal, middleware, and reload behavior.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_storage
dart analyze --fatal-infos packages/routed_storage
dart test packages/routed_storage/test
```

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use `routed` for the full provider catalogue or
  `routed_core` plus explicit adapters for slim compositions.
- Routed adapters depend on `routed_core` and matching `server_*` runtimes;
  they must not depend on the batteries-included `routed` facade.
- Host I/O belongs in `routed_io`, `routed_node`, or `server_native`, not in
  feature adapters.
- Framework-agnostic `server_*` implementations must not import Routed from
  `lib/`.
