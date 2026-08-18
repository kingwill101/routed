# routed_storage

Routed adapter for [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) — `StorageManager`, local disks, and declarative static mounts.

Wraps `server_storage` for `routed` `EngineContext.storageManager` / `storageDisk` and `storageMiddleware` / `RoutedStorageProvider`.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_core: ^0.3.3
  routed_storage: ^0.1.0
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
      RoutedStorageProvider(manager),
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

`RoutedStorageProvider` binds the manager for application code. The
`RoutedStaticProvider` adds the optional `static.mounts` configuration:

```dart
final engine = await Engine.create(
  configItems: {
    'static': {
      'enabled': true,
      'mounts': [
        {'route': '/assets', 'disk': 'local'},
      ],
    },
  },
  providers: [
    RoutedStorageProvider(manager),
    RoutedStaticProvider(),
  ],
);
```

With the batteries-included `routed` package, call
`registerRoutedProviders()` and list `routed.storage` and `routed.static` in
`http.providers` when using a provider manifest. An explicitly supplied
`StorageManager` remains authoritative; config-created local disks use the
manager's default file system.

See [`example/storage_example.dart`](example/storage_example.dart).

## Testing

```bash
dart test packages/routed_storage
dart analyze --fatal-infos packages/routed_storage/lib
```
