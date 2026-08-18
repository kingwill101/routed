# routed_analyzer

Analyzer plugin and lint rules for Routed.

This package contains the Routed analyzer plugin implementation and lint rules
for route schema and validation metadata.

## Activation

Installing `routed_analyzer` as a dependency is **not** enough for its
lint rules to run: the plugin must also be listed in the `plugins` section of
your project's (or workspace's) `analysis_options.yaml` (Dart 3.10+ analyzer
plugin system):

```yaml
plugins:
  routed_analyzer: ^0.1.0
```

When developing locally, a path reference works too:

```yaml
plugins:
  routed_analyzer:
    path: /path/to/routed_analyzer
```

Restart the analysis server (or reload the IDE) after changing the `plugins`
section for changes to take effect.

The plugin registers the following lint rules:

- `missing_route_schema` — route registered without `schema:` metadata
- `missing_schema_summary` — `RouteSchema` without a `summary`
- `missing_schema_response` — `RouteSchema` without any `responses`
- `invalid_validation_rule` — unrecognized pipe rule in `validationRules`
- `schema_deprecated_without_description` — deprecated route without
  explaining why

## Requirements

- Dart SDK `>=3.9.0`
- An IDE or analysis server supporting analyzer plugins (VS Code, IntelliJ,
  or the Dart CLI analysis server)

This is a development-time analyzer plugin, not an `Engine` provider. It does
not belong in a Routed application's runtime provider list.
