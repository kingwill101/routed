# routed

Batteries-included Routed framework: core engine plus official feature packages.

## Install

```bash
dart pub add routed
```

## Full-featured application

Call `registerRoutedProviders()` before creating the engine. This fills the
shared provider registry; `Engine.create()` then initializes the registered
official providers.

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  registerRoutedProviders();
  final engine = await Engine.create();

  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.serve(port: 8080);
}
```

The package includes a runnable version of this setup. From the package root,
run it with:

```bash
dart run example/full_example.dart
```

## Typed provider composition

For a smaller application, pass only the providers it needs. Supplying a
`providers` list replaces the full built-in list, so keep the core providers
and add the feature providers required by the application:

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedCacheProvider(CacheConfig(store: ArrayStore())),
    ],
  );

  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.serve(port: 8080);
}
```

Provider-specific configuration belongs in typed provider constructors before
startup. Routed does not use YAML files or dotted-key configuration for these
settings. Use `Engine.builtins` when the application wants the complete
registered catalogue without listing providers manually.

For a slim engine with no feature-package dependency, depend directly on
`package:routed_core` and use `Engine.defaultProviders`.
