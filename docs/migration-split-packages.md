# Modular packages layout

## Names

| Package | Use for |
|---------|---------|
| `package:routed` | Apps — batteries included |
| `package:routed_core` | Slim engine / adapter dependencies |
| `package:routed_*` | Individual features |
| `package:server_*` | Portable domain runtimes |

## App

```yaml
dependencies:
  routed: ^0.3.3
```

```dart
import 'package:routed/routed.dart';

void main() async {
  final engine = Engine(providers: Engine.defaultProviders);
  // official feature providers are registered by importing package:routed
}
```

## Adapter package

```yaml
dependencies:
  routed_core: ^0.3.3
  server_cache: ^0.1.0  # example
```

```dart
import 'package:routed_core/routed_core.dart';
```

## Selective (no batteries)

```yaml
dependencies:
  routed_core: ^0.3.3
  routed_sessions: ^0.1.0
  routed_http: ^0.1.0
```
