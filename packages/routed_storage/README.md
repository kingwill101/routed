# routed_storage

Routed adapter for [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) — `StorageManager`, local disks, and declarative static mounts.

Wraps `server_storage` for `routed` `EngineContext.storageManager` / `storageDisk` and `storageMiddleware` / `RoutedStorageProvider`.

## Install

```yaml
dependencies:
  routed: ^0.5.0
  routed_core: ^0.5.0
  routed_storage: ^0.2.0
  server_storage: ^0.1.0
```

## Usage

```dart
import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:server_storage/server_storage.dart';

void main() async {
  final fs = MemoryFileSystem();
  final manager = StorageManager(defaultFileSystem: fs)
    ..registerDisk(
      'local',
      LocalStorageDisk(root: '/tmp/storage', fileSystem: fs),
    )
    ..setDefault('local');

  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedStorageProvider(manager: manager),
    ],
  );
  engine.use(storageMiddleware(manager));

  engine.get('/files/:path', (ctx) {
    final disk = ctx.storageDisk();
    return ctx.json({'disk': disk.resolve(ctx.param('path')!)});
  });

  await engine.serve(port: 8080);
}
```

`RoutedStorageProvider` binds the manager for application code. Static mounts
are supplied as typed configuration:

```dart
final engine = await Engine.create(
  providers: [
    RoutedStorageProvider(manager: manager),
    RoutedStaticProvider(
      StaticConfig(
        enabled: true,
        mounts: [StaticMountConfig(route: '/assets', disk: 'local')],
      ),
    ),
  ],
);
```

With the batteries-included `routed` package, call
`registerRoutedProviders()` and include the typed providers you need in the
engine's provider list. An explicitly supplied `StorageManager` remains
authoritative; otherwise pass `StorageConfig` as `configuration` to define
local disks with `LocalStorageDiskConfig`. Configured providers are immutable
for the lifetime of an engine.

The package includes a runnable storage example under its `example` directory.

## Testing

```bash
dart test packages/routed_storage
dart analyze --fatal-infos packages/routed_storage/lib
```
