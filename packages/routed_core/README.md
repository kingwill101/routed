# routed_core

Slim HTTP engine for the Routed ecosystem (`Engine`, `EngineContext`, `Router`).

## Provider setup

`routed_core` owns only the core and routing providers. Initialize them
explicitly when building a slim application:

```dart
import 'package:routed_core/routed_core.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: Engine.defaultProviders,
  )..get('/health', (ctx) => ctx.json({'ok': true}));

  await engine.serve(port: 8080);
}
```

Feature adapters such as `routed_sessions` or `routed_views` are added to the
provider list alongside `Engine.defaultProviders`. Applications that want the
official feature bundle should depend on
[`package:routed`](https://pub.dev/packages/routed), call
`registerRoutedProviders()`, and then use `Engine.create()`. Adapter packages
depend on `routed_core` directly.
