---
name: routed-openapi
description: Maintain, extend, document, test, or troubleshoot the routed_openapi subsystem in the Routed Dart monorepo. Use when a task touches routed_openapi APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_openapi

This skill is the complete working guide for the `routed_openapi` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_openapi`
- **Directory:** `packages/routed_openapi`
- **Version in this checkout:** `0.1.0`
- **Role:** OpenAPI route metadata and manifest generation
- **Purpose:** Portable OpenAPI metadata extraction and generation for Routed routes. It enriches RouteBuilder metadata, extracts manifests, and converts them into OpenAPI specs without registering a runtime provider.

### Public API

- Fluent `RouteBuilder` extensions include `summary`, `description`, `tags`, `operationId`, `deprecated`, `hidden`, `responseSchema`, `paramSchema`, and `bodySchema` metadata.
- Annotations include `Summary`, `Description`, `Tags`, `OperationId`, `ApiDeprecated`, `ApiHidden`, `ApiResponse`, `ApiParam`, and `ApiBody`.
- `RouteSchema`, `BodySchema`, `ParamSchema`, and `ResponseSchema` describe route contracts.
- `OpenApiSpec` and its path/operation/schema models represent generated output; `OpenApiConfig` controls manifest-to-spec generation.
- `OpenApiBuilder`, metadata extraction/merging, handler identity, pipe-rule conversion, and schema validation form the build pipeline.

### Public imports

- `package:routed_openapi/routed_openapi.dart`

### Runtime package dependencies

- `routed_core`
- `routed_validation`

### Composition rules

- Attach metadata to route builders so nested groups and mounted routers carry cumulative prefixes into the manifest.
- Use routed_openapi_builder as the dev-time builder and routed_cli to generate the runtime manifest before build_runner.
- Keep this package free of runtime provider registration; it reads route metadata rather than booting an Engine service.

### Known hazards

- Do not reconstruct route graphs heuristically when the manifest is available.
- For dynamic prefixes or inline closures, attach fluent metadata directly for deterministic output.
- Preserve nested group prefix flattening, response status codes, hidden/deprecated flags, and validation-to-schema conversion.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_openapi/routed_openapi.dart';

final engine = await Engine.create(providers: Engine.defaultProviders);
engine.post('/users', (ctx) => ctx.json({'created': true}, statusCode: 201))
  .summary('Create a user')
  .tags(['Users'])
  .responseSchema(const ResponseSchema(201, description: 'User created'));
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_openapi`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a `lib/src` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

Cover fluent metadata, annotations, nested groups/mounted routers, schema validation, handler identity, pipe-rule conversion, manifest extraction, and final OpenAPI JSON.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_openapi
dart analyze --fatal-infos packages/routed_openapi
dart test packages/routed_openapi/test
```

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use `routed` for the full provider catalogue or
  `routed_core` plus explicit adapters for slim compositions.
- Routed adapters depend on `routed_core` and matching `server_*` runtimes;
  they must not depend on the batteries-included `routed` facade.
- Host I/O belongs in `routed_io`, `routed_node`, or `server_native`, not in
  feature adapters.
- Framework-agnostic `server_*` implementations must not import Routed from
  `lib/`.
