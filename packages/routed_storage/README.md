# routed_storage

Routed adapter for [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) — `StorageManager`, `StorageDisk` (local/cloud), `S3` drivers.

Wraps `server_storage` for `routed` `EngineContext.storageManager` / `storageDisk` and `storageMiddleware` / `RoutedStorageProvider`.

## Install

```yaml
dependencies:
  routed: ^0.3.3
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
    ..registerDisk('local', LocalStorageDisk(fs, '/tmp/storage'))
    ..setDefault('local');

  final engine = Engine();
  engine.use(storageMiddleware(manager));

  engine.get('/files/:path', (ctx) {
    final disk = ctx.storageDisk();
    return ctx.json({'disk': disk.resolve(ctx.param('path')!)});
  });

  await engine.serve(port: 8080);
}
```

See [`example/storage_example.dart`](example/storage_example.dart).

## Testing

```bash
dart test packages/routed_storage
dart analyze --fatal-infos packages/routed_storage/lib
```
