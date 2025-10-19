# jaspr_routed

Jaspr integration helpers for the [Routed](https://github.com/kingwill101/routed) backend.

## Getting Started

Add `jaspr_routed` to your `pubspec.yaml` (already part of the workspace) and initialize Jaspr before registering
routes:

```dart
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_routed/jaspr_routed.dart';
import 'package:routed/routed.dart';

void main() async {
  Jaspr.initializeApp();

  final router = Router()
    ..get('/hello', jasprRoute((ctx) {
      return Component.text('Hello from ${ctx.request.uri.path}');
    }));

  await Engine(router: router).run();
}
```

## Features

| Feature                  | Description                                                                                                                      |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| `jasprRoute`             | Converts a Routed route handler into a Jaspr render pipeline backed by `serveApp`.                                               |
| `InheritedEngineContext` | Makes the current `EngineContext`, `Request`, `Response`, and `Session` visible to Jaspr components via `context.engineContext`. |

## Notes

- The helper is server-only; attempts to import it in a browser build will throw assertions via stub implementations.
- Ensure the session middleware is registered if you plan to access `context.engineContext.session` inside components.
- Check out `example/` for a Routed port of the Jaspr + Serverpod demo (entrypoint: `bin/server.dart`). Because it uses
  `@client` components, run `jaspr build clients` inside `packages/jaspr_routed/example/` before starting the server so
  the generated `main.clients.dart.js` file can be served.
