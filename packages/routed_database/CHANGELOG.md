# Changelog

## 0.1.0

- Add an Ormed-backed named database manager.
- Add manager migration delegation and opt-in provider boot migrations.
- Run provider-owned initialization and optional migrations in Routed's awaited
  service-provider boot lifecycle, before request handling begins.
- Add `RoutedDatabaseProvider`, request middleware, and `EngineContext` helpers.
- Support codegen-free database access through `OrmDatabase`.
