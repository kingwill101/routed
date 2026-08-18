# routed_logging

HTTP logging provider and request logger helpers for Routed.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_core: ^0.3.3
  routed_logging: ^0.1.0
```

## Initialize and use

Call `registerRoutedProviders()` when using the `routed` facade so
`routed.logging` is included. A slim engine must add `LoggingServiceProvider`
explicitly:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_logging/routed_logging.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      LoggingServiceProvider(),
    ],
  );

  engine.get('/health', (ctx) {
    ctx.logger.info('health check');
    return ctx.json({'ok': true});
  });

  await engine.serve(port: 8080);
}
```

Provider configuration belongs under the normal logging configuration keys.
Use `registerRoutedLoggingProviders()` when resolving `routed.logging` from a
configuration manifest without importing `package:routed/routed.dart`.
