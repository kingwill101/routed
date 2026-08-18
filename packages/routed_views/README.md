# routed_views

View rendering and translation helpers for Routed. The package owns the view
engines, view provider, localization provider, locale resolvers, and
`EngineContext` extensions for rendering templates and translating messages.

## Install

```yaml
dependencies:
  routed_core: ^0.3.3
  routed_views: ^0.1.0
```

Most applications can import `package:routed/routed.dart`, which re-exports
these APIs and registers the standard view/localization providers. Import this
package directly when composing a smaller engine or a custom provider list:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      ViewServiceProvider(),
      LocalizationServiceProvider(),
    ],
  )..get('/welcome', (ctx) async {
    return ctx.view('welcome.liquid', data: {'name': 'Routed'});
  });

  await engine.serve(port: 8080);
}
```

The package also provides `ctx.template(...)`, `ctx.viewTrans(...)`,
`ctx.viewTransChoice(...)`, locale resolvers, and Liquid/Mustache view engine
building blocks. Configure view directories and translation sources through
the standard Routed configuration system.
