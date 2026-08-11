# Driver Registries

Routed now exposes public registration APIs for every subsystem that resolves pluggable drivers:

- `StorageServiceProvider.registerDriver` accepts a builder that returns a `StorageDisk`.
- `CacheManager.registerDriver` installs cache store factories and is reused by the built-in array/file/null stores.
- `SessionServiceProvider.registerDriver` wires session stores through the same builder context used by the framework
  defaults.

All built-in drivers are registered through these entrypoints, so custom implementations exercise the identical
resolution path. Override an existing driver by passing `overrideExisting: true`, or register new driver identifiers
before the engine boots. Configuration errors surface the driver name and the registered options when a lookup fails.

## Documenting Driver-Specific Options

Driver registrations can also advertise their configuration surface. Pass a `documentation` callback when calling
`registerDriver` (storage, cache, or session) and return one or more `ConfigDocEntry` instances. Each callback receives
a doc context that exposes the driver name and the config path template (`storage.disks.*`, `cache.stores.*`, or
`session`). The provider merges these entries into its default config docs, so custom drivers show up alongside
built-ins in generated documentation or CLI inspection tools.
