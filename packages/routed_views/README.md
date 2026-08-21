# routed_views

View rendering and translation helpers for Routed. The package owns the view
engines, view provider, localization provider, locale resolvers, and
`EngineContext` extensions for rendering templates and translating messages.

## Install

```yaml
dependencies:
  routed_core: ^0.5.0
  routed_views: ^0.2.0
```

Most applications can import `package:routed/routed.dart`, which re-exports
these APIs and registers the standard view/localization providers. Import this
package directly when composing a smaller engine or a custom provider list.
Pass `RoutedViewConfig` and `LocalizationConfig` to the providers when the
defaults need to change:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      ViewServiceProvider(RoutedViewConfig(directory: 'views')),
      LocalizationServiceProvider(
        LocalizationConfig(defaultLocale: 'en', paths: ['resources/lang']),
      ),
    ],
  )..get('/welcome', (ctx) async {
    return ctx.view('welcome.liquid', data: {'name': 'Routed'});
  });

  await engine.serve(port: 8080);
}
```

Custom locale resolution is supplied as a resolver instance in the typed
configuration, for example `LocalizationConfig(resolvers: [MyResolver()])`.

The package also provides `ctx.template(...)`, `ctx.viewTrans(...)`,
`ctx.viewTransChoice(...)`, locale resolvers, and Liquid/Mustache view engine
building blocks. View directories and translation sources are configured with
the typed provider constructors; the configuration is fixed for the engine's
lifetime.
