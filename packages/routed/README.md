# routed

Batteries-included Routed framework: core engine plus official feature packages.

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  // Provider registration is explicit so minimal compositions stay possible.
  registerRoutedProviders();
  final engine = await Engine.create(
    configItems: {'app.name': 'My Routed app'},
  );

  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.serve(port: 8080);
}
```

Call `registerRoutedProviders()` once before `Engine.create()` for the
batteries-included setup. For a smaller composition, pass an explicit provider
list such as
`[...Engine.defaultProviders, RoutedCacheProvider()]`. Provider-specific
configuration belongs in `config/http.yaml` or `configItems`, and provider
middleware is enabled by the package's normal manifest/configuration rules.

For the slim engine only, depend on [`routed_core`](../routed_core).
