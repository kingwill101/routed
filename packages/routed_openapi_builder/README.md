# routed_openapi_builder

Build-time OpenAPI generation for Routed applications.

## Install

```yaml
dev_dependencies:
  routed_openapi_builder: ^0.1.0
```

The builder consumes the runtime route manifest produced by the CLI. It does not
reconstruct or guess the route graph from source code:

```bash
dart run routed_cli openapi generate
dart run build_runner build --delete-conflicting-outputs
```

The generated files are:

- `lib/generated/openapi.json`
- `lib/generated/openapi_controller.g.dart`

The runtime manifest is authoritative, including routes created through nested
groups, mounted routers, and controllers. Nested groups can be arbitrarily deep;
the builder emits their cumulative prefixes as flattened OpenAPI paths.

Static annotation and Dartdoc enrichment is most reliable with literal group
prefixes and named handlers. For dynamically computed prefixes or inline closure
handlers, attach fluent metadata directly to the `RouteBuilder` when exact
OpenAPI output is required.

The builder is dev-time tooling, not a runtime provider. Your application still
initializes its engine with `Engine.create()` and the appropriate provider list;
the builder only consumes the resulting route manifest.
