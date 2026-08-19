# Driver Registries

Routed now exposes public registration APIs for every subsystem that resolves pluggable drivers:

- `StorageServiceProvider.registerDriver` accepts a builder that returns a `StorageDisk`.
- `CacheManager.registerDriver` installs cache store factories and is reused by the built-in array/file/null stores.
- `SessionServiceProvider.registerDriver` wires session stores through the same builder context used by the framework
  defaults.

All built-in drivers are registered through these entrypoints, so custom implementations exercise the identical
resolution path. Override an existing driver by passing `overrideExisting: true`, or register new driver identifiers
before the engine boots. Configuration errors surface the driver name and the registered options when a lookup fails.

Driver registries do not generate configuration schemas or documentation. Define driver options as Dart configuration
values, validate them in the provider, and document the public constructor or driver context alongside the
implementation.
