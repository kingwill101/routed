# server_storage
Framework-agnostic storage runtime for local and cloud-backed disks.

## S3-compatible storage

`S3StorageDisk` supports AWS S3 and compatible services such as Cloudflare R2,
DigitalOcean Spaces, and MinIO:

```dart
import 'dart:io';

import 'package:server_storage/server_storage.dart';

final environment = Platform.environment;
final s3 = S3StorageDisk(
  endpoint: 'https://<account-id>.r2.cloudflarestorage.com',
  accessKey: environment['S3_ACCESS_KEY']!,
  secretKey: environment['S3_SECRET_KEY']!,
  bucket: 'uploads',
  region: 'auto',
  pathStyle: true,
  prefix: 'production',
);

final manager = StorageManager()
  ..registerDisk('uploads', s3)
  ..setDefault('uploads');

await manager.storage().put(
  'avatars/user-1.png',
  <int>[/* file bytes */],
);
```

The endpoint can be a bare host or an HTTPS URL. Cleartext HTTP is rejected by
default. Local MinIO development can opt in explicitly with an endpoint such
as `http://127.0.0.1:9000` and `allowInsecureHttp: true`; never enable that
option for credentials or object data crossing an untrusted network.
Construction is network-free. For a development service where the application
may create its bucket, set `autoCreateBucket: true` and call
`await s3.ensureReady()` during startup. Production buckets should normally be
provisioned separately.

The disk roots object operations inside its configured prefix, including
reads, writes, listings, and signed URLs, without requiring application code
to prepend it.

`manager.storage('uploads')` returns the same `Filesystem` API for local and S3
disks, with methods including `put`, `get`, `readStream`, `exists`, `delete`,
and metadata operations. S3 objects are treated as private: attempts to set
`visibility: 'public'` are rejected because the current driver cannot apply a
truthful per-object ACL. Generate a temporary download URL instead:

```dart
final downloadUrl = await manager.temporaryUrl(
  'reports/monthly.pdf',
  DateTime.now().add(const Duration(minutes: 10)),
  disk: 'uploads',
);
```

Presigning fails closed. It never falls back to an unsigned `publicUrl` when
the driver cannot create a signature. Supplying `publicUrl` is an explicit
opt-in for a separately configured public bucket or CDN and bypasses this
private-by-default model. Provider SDKs and `file_cloud` remain implementation
details of `server_storage`; application code uses only the manager API.

## SFTP storage

[`file_sftp`](https://pub.dev/packages/file_sftp) provides the SFTP transport.
`SftpStorageDisk` adapts its typed configuration to the same application-scoped
manager API:

```dart
final environment = Platform.environment;
final sftp = SftpStorageDisk(
  config: SftpConfig(
    host: environment['SFTP_HOST']!,
    port: int.tryParse(environment['SFTP_PORT'] ?? '') ?? 22,
    username: environment['SFTP_USERNAME']!,
    password: environment['SFTP_PASSWORD'],
    root: '/srv/uploads',
    readOnly: false,
  ),
  diskName: 'archive',
);

manager.registerDisk('archive', sftp);
await manager.storage('archive').put('reports/daily.json', reportJson);

// During application shutdown:
await sftp.close();
```

Private-key authentication is available through `privateKeyPems` and
`privateKeyPassphrase`. Connections are lazy, remote roots must be absolute,
and callers should close the disk during application shutdown.

## Using with Routed

`server_storage` does not register an `Engine` provider. Use the
`routed_storage` adapter to initialize `RoutedStorageProvider` and
`storageMiddleware`, or use the standard `routed` facade and configure the
storage adapter there.

`routed_storage` re-exports the server storage API, so Routed applications can
construct `S3StorageDisk` without a second storage import.

Host-native object stores that cannot expose a synchronous `package:file`
filesystem can still participate in application storage through
`manager.registerFilesystem(name, filesystem)`. They are available from
`manager.storage(name)` and Routed's `ctx.storage(name)`. They do not support
`manager.disk(name)` or local path resolution, but `routed_storage` can serve
truthfully public objects through `RoutedStaticProvider` or
`engine.staticStorage()`, and private objects through `engine.signedStorage()`,
using their asynchronous streams and metadata.

Ordinary storage-backed static handlers serve only objects whose adapter
truthfully reports `public` visibility. Use `engine.signedStorage()` for
private objects; it verifies a time-limited HMAC capability before reading
storage.
