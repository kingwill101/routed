## Unreleased

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.

## 0.2.0

- **Breaking:** Replace the string-based `StorageDiskConfig.driver` field with
  the typed `LocalStorageDiskConfig`; storage configuration now applies all
  declared disks when no manager is supplied.
- Added declarative, storage-backed static mounts through the Routed provider
  system.
- Aligned static-file handling with the current storage manager APIs.

## 0.1.0
- Initial adapter (PR H)
