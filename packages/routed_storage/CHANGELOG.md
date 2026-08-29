# Changelog

## Unreleased

- Static mounts can now serve storage-only `storage_fs` filesystems registered
  with `StorageManager.registerFilesystem()`, including native Cloudflare R2
  bindings.
- Added `Engine.staticStorage()` and `Router.staticStorage()` for imperative
  stream-backed static endpoints.
- Require `server_storage` 0.1.3 or later, the first release containing the
  storage-only manager and static-handler APIs used by this package.
- Prefer asynchronous `storage_fs` serving for operational disks so remote
  filesystems do not enter synchronous `package:file` listing paths.
- Added `Engine.signedStorage()` and `Router.signedStorage()` for private
  objects exposed only through time-limited signed URLs.
- Added request-scoped `temporaryStorageUrl()` and
  `temporaryStorageUploadUrl()` helpers for provider-signed URLs without
  exposing storage-driver implementations.
- Storage-backed static mounts now fail closed on private/unknown visibility
  and omit private filenames from directory listings.

## 0.2.1 - 2026-08-25

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.
- Clarified typed storage configuration, provider lifecycle, static mounts,
  and the Routed response-sink integration in the public API docs.

## 0.2.0

- **Breaking:** Replace the string-based `StorageDiskConfig.driver` field with
  the typed `LocalStorageDiskConfig`; storage configuration now applies all
  declared disks when no manager is supplied.
- Added declarative, storage-backed static mounts through the Routed provider
  system.
- Aligned static-file handling with the current storage manager APIs.

## 0.1.0
- Initial adapter (PR H)
