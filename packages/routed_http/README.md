# routed_http

HTTP utilities for Routed: request binding, multipart parsing, content
negotiation, response compression, Server-Sent Events, and conditional
requests.

## Install

```yaml
dependencies:
  routed_core: ^0.3.3
  routed_http: ^0.1.0
```

Import `package:routed_http/routed_http.dart` to add the HTTP extensions to
`EngineContext`:

```dart
import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:routed_http/routed_http.dart';

Future<void> main() async {
  final engine = await Engine.create(providers: Engine.defaultProviders)
    ..get('/events', (ctx) async {
      await ctx.sse(
        Stream.value(SseEvent(data: '{"status":"ready"}')),
      );
    });

  await engine.serve(port: 8080);
}
```

The package includes JSON, form, query, URI, and multipart bindings; binding
extensions such as `ctx.bind(...)`, `ctx.bindJSON(...)`, and
`ctx.bindQuery(...)`; content negotiation; ETag and conditional-request
helpers; SSE encoding/streaming; and an opt-in gzip provider for buffered
responses.

To use compression directly from this package, register the HTTP providers
before creating the engine:

```dart
registerRoutedHttpProviders();
final engine = await Engine.create(configItems: {
  'compression.enabled': true,
});
```

Use `routed_http` directly when you need these utilities without importing the
full `routed` facade. The facade re-exports the package for batteries-included
applications.
