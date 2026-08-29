## 0.1.3 - 2026-08-29

- Added a first-class `S3StorageDisk` for AWS S3 and compatible services,
  including endpoint, region, temporary-credential, key-prefix, path-style,
  public-URL, and optional bucket-bootstrap configuration.
- Added application-scoped Laravel-style filesystem access through
  `StorageManager.storage()` / `drive()` for both built-in local and S3 disks.
- Added `StorageManager.temporaryUrl()` and `temporaryUploadUrl()` so
  applications can issue provider-signed URLs without accessing `file_cloud`
  or an underlying cloud adapter.
- Added `StorageManager.registerFilesystem()` for host-native object stores
  that expose `storage_fs` operations without a `package:file` filesystem.
- Added `StorageFileHandler` and explicit path-resolution capability checks so
  host-native filesystems can back framework static endpoints without
  importing `dart:io` in the portable handler.
- Added `SftpStorageDisk`, backed by `file_sftp`, with password/private-key
  authentication, rooted remote paths, read-only mode, lazy connections, and
  explicit connection cleanup.
- Widened the `storage_fs`, `file_cloud`, and `file_sftp` dependency ranges to
  `<1.0.0` so applications can select compatible 0.x adapter versions.
- Hardened cloud object-key resolution against absolute paths and parent-path
  escapes.
- Fixed local visibility changes so `chmod` targets the configured storage
  root and reports command failures.
- Fixed prefixed S3 public URLs so they point at the stored object key.
- Fixed storage-backed static directory detection for index and listing
  requests on hierarchical filesystems.
- Added `StorageSignedUrlSigner` and `SignedStorageFileHandler` for
  HMAC-SHA256, time-limited private downloads with timing-safe verification.
- Made ordinary storage-backed static serving require truthful public
  visibility and filter private entries from directory listings.
- Made S3 storage private by default: public visibility requests are rejected
  and failed presigning no longer falls back to an unsigned public URL.

## 0.1.2 - 2026-08-25

- Migrated package analysis to `very_good_analysis` and completed public API
  Dartdoc coverage.
- Expanded storage-manager, local-disk, cloud-disk, and static-file lifecycle
  guidance, including path-boundary behavior.

## 0.1.1

- Hardened local-disk path resolution against directory escapes and invalid
  disk names.
- Added file handling needed by storage-backed static mounts.

## 0.1.0
- Initial extraction from server_data/src/storage (PR H)
