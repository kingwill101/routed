# routed_logging

HTTP logging provider and request logger helpers for Routed.

## Install

```yaml
dependencies:
  routed: ^0.5.0
  routed_core: ^0.5.0
  routed_logging: ^0.2.0
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

Provider configuration is supplied with the typed `LoggingConfig` constructor,
for example `LoggingServiceProvider(LoggingConfig(errorsOnly: true))`.
There is no YAML or dotted-key configuration path. If you use the package's
provider catalogue directly, call `registerRoutedLoggingProviders()` before
engine creation; otherwise construct `LoggingServiceProvider` in the provider
list as shown above.
