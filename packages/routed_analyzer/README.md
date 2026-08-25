# routed_analyzer

Analyzer plugin and route-documentation warnings for Routed.

`routed_analyzer` helps keep route metadata useful to humans and generated
OpenAPI documents. It checks route registrations, `RouteSchema` summaries and
responses, deprecations, and literal validation-rule pipe strings while you
work in an IDE or run `dart analyze`.

## Activation

Installing `routed_analyzer` as an ordinary dependency is **not** enough for
its rules to run. Enable it in the top-level `plugins` section of the
`analysis_options.yaml` at your package or workspace root. This is the Dart
3.10+ analyzer plugin system (Flutter 3.38+):

```yaml
plugins:
  routed_analyzer: ^0.1.1
```

The `plugins` section is top-level; it does not go under `analyzer`. Do not
put it in a nested analysis-options file because the analysis server only
loads plugin configuration from the package or workspace root.

When developing locally, a path reference works too:

```yaml
plugins:
  routed_analyzer:
    path: /path/to/routed_analyzer
```

Restart the analysis server (or reload the IDE) after changing the `plugins`
section for changes to take effect.

The package registers warnings, so all of the rules below are active as soon
as the plugin is enabled. Suppress one diagnostic at a specific location with
the plugin-qualified diagnostic name:

```dart
// ignore: routed/missing_route_schema
router.get('/health', healthHandler);
```

Use `ignore_for_file` when a generated or intentionally undocumented file
needs a file-wide exception:

```dart
// ignore_for_file: routed/missing_schema_response
```

The plugin registers the following lint rules:

- `missing_route_schema` — route registered without `schema:` metadata
- `missing_schema_summary` — `RouteSchema` without a `summary`
- `missing_schema_response` — `RouteSchema` without any `responses`
- `invalid_validation_rule` — unrecognized pipe rule in `validationRules`
- `schema_deprecated_without_description` — deprecated route without
  explaining why

For example, a documented route can satisfy the schema rules in one place:

```dart
router.get(
  '/users',
  listUsers,
  schema: RouteSchema(
    summary: 'List users',
    description: 'Returns the users visible to the current caller.',
    responses: [
      ResponseSchema(200, description: 'A JSON user list.'),
    ],
  ),
);
```

## Requirements

- Dart SDK `>=3.9.0`
- An IDE or analysis server supporting analyzer plugins (VS Code, IntelliJ,
  or the Dart CLI analysis server)

This is a development-time analyzer plugin, not an `Engine` provider. It does
not belong in a Routed application's runtime provider list.

## Provider inspection

The public `ProviderMetadata` and `inspectProviders` APIs are for development
tools that need to display the providers registered with Routed. They report
provider and typed-configuration type names, not configuration values, and
invoking `inspectProviders()` invokes each registered provider factory. Keep
the call out of request handling when factories perform setup or allocate
resources.
