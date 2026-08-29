# routed_storage

Routed adapter for [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) — `StorageManager`, local disks, and declarative static mounts.

Wraps `server_storage` for `routed` `EngineContext.storageManager` / `storageDisk` and `storageMiddleware` / `RoutedStorageProvider`.

## Install

```yaml
dependencies:
  routed: ^0.5.0
  routed_core: ^0.5.0
  routed_storage: ^0.2.0
  server_storage: ^0.1.3
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

The same mount works for a storage-only filesystem registered with
`registerFilesystem()`. For imperative composition, mount the asynchronous
filesystem directly:

```dart
engine.staticStorage(
  '/assets',
  manager.storage('public-assets'),
  rootPath: 'public',
);
```

Storage-backed static mounts require `public` object visibility and fail
closed when visibility is private, unknown, or cannot be read. Private object
stores such as Cloudflare R2 should use a signed mount:

```dart
final signer = StorageSignedUrlSigner(environment['STORAGE_SIGNING_KEY']!);

engine.signedStorage(
  '/downloads',
  manager.storage('r2'),
  signer: signer,
  rootPath: 'private',
);

// Run authentication and object-level authorization before issuing this URL.
final url = signer.sign(
  Uri.parse('https://app.example.com/downloads/report.pdf'),
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
);
```

The secret must contain at least 32 UTF-8 bytes and belong in the host's
secret manager. Signed downloads return `Cache-Control: private, no-store`;
unsigned, expired, and tampered URLs are rejected before any storage read.

S3-compatible disks come from `server_storage` and are re-exported here:

```dart
import 'dart:io';

import 'package:routed_storage/routed_storage.dart';

final environment = Platform.environment;
final s3 = S3StorageDisk(
  endpoint: 'https://<account-id>.r2.cloudflarestorage.com',
  accessKey: environment['S3_ACCESS_KEY']!,
  secretKey: environment['S3_SECRET_KEY']!,
  bucket: 'assets',
  region: 'auto',
  pathStyle: true,
);

final manager = StorageManager()
  ..registerDisk('assets', s3)
  ..setDefault('assets');

final engine = await Engine.create(
  providers: [RoutedStorageProvider(manager: manager)],
);

engine.get('/files/:path', (ctx) async {
  final storage = ctx.storage();
  final path = ctx.param('path')!;
  return ctx.json({
    'exists': await storage.exists(path),
    'contents': await storage.get(path),
  });
});
```

SFTP uses the same manager and request API:

```dart
final sftp = SftpStorageDisk(
  config: SftpConfig(
    host: environment['SFTP_HOST']!,
    username: environment['SFTP_USERNAME']!,
    password: environment['SFTP_PASSWORD'],
    root: '/srv/uploads',
  ),
);

manager.registerDisk('archive', sftp);
await manager.storage('archive').put('reports/daily.json', reportJson);
```

Call `await sftp.close()` during application shutdown.

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
