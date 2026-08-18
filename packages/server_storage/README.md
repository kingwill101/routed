# server_storage
Framework-agnostic storage runtime for local and cloud-backed disks.

## Using with Routed

`server_storage` does not register an `Engine` provider. Use the
`routed_storage` adapter to initialize `RoutedStorageProvider` and
`storageMiddleware`, or use the standard `routed` facade and configure the
storage adapter there.
