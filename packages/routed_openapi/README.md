# routed_openapi

OpenAPI extraction and generation for Routed — portable OpenAPI spec generation from route manifests.

Wraps `server_*` OpenAPI tooling for `routed` `Engine` via build-time extraction (`routed_openapi_builder`) and runtime generation.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_core: ^0.3.3
  routed_openapi: ^0.1.0
```

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_openapi/routed_openapi.dart';

Future<void> main() async {
  final engine = await Engine.create(providers: Engine.defaultProviders);

  engine
      .post('/users', (ctx) => ctx.json({'created': true}, statusCode: 201))
      .summary('Create a user')
      .tags(['Users'])
      .responseSchema(
        const ResponseSchema(201, description: 'User created'),
      );
}
```

`routed_openapi` is a route-metadata and build-time package; it does not
register a runtime service provider. Initialize the core providers yourself,
or call `registerRoutedProviders()` before `await Engine.create()` from
`package:routed/routed.dart` in a batteries-included application.

Fluent metadata is attached to the runtime route and therefore follows nested
groups and mounted routers into the generated manifest. Nested groups may be
arbitrarily deep; their prefixes are flattened into the final OpenAPI paths.

For static output, install `routed_openapi_builder` as a dev dependency, then run:

```bash
dart run routed_cli openapi generate
dart run build_runner build --delete-conflicting-outputs
```

See `example/` and `test/` for additional examples.

## Testing

```bash
dart test
```
