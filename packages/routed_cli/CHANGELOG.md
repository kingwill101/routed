## 0.2.0

- Rebuilt the config generator on Routed’s config snapshot utilities so derived
  defaults (storage roots, cache/session fallbacks, env metadata) match the
  engine’s provider docs exactly.
- `provider:list --config` now prints the new config snapshots (values + doc
  entries) and the manifest commands stop writing the legacy `features` block,
  keeping `config/http.yaml` in sync with the engine schema.
- `create` scaffolds now include the `STORAGE_ROOT` env var, add the `args`
  dependency automatically, and type the generated `server.dart` entrypoint with
  `Engine` imports to satisfy the analyzer.

## 0.1.0

- `create` adds `api`, `web`, and `fullstack` templates with tailored scaffolds.
- Routed CLI now loads project-defined commands from `lib/commands.dart`, exposing them alongside the built-ins and
  guarding against name collisions.
- `provider:list --config` now fails early when duplicate driver registrations are detected and prints guidance for
  resolving the conflicting IDs.

## 0.0.1

- Initial version.
