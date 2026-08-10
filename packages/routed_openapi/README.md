# routed_openapi

OpenAPI extraction and generation for Routed — portable OpenAPI spec generation from route manifests.

Wraps `server_*` OpenAPI tooling for `routed` `Engine` via build-time extraction (`routed_openapi_builder`) and runtime generation.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_openapi: ^0.1.0
```

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_openapi/routed_openapi.dart';
```

See `example/` and `test/` for pre-move tests reused from `routed` OpenAPI suite.

## Testing

```bash
dart test
```
