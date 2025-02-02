
# Fallback Route Example

This example demonstrates how to use the fallback route feature with Routed. In this example, any HTTP request that does not match a defined route will be handled by a fallback handler.

## Overview

The fallback route is defined using the `engine.fallback(...)` method. When an incoming request doesn't match any registered route, the engine will automatically invoke this fallback handler. This is handy to catch all unmatched requests and return a custom response rather than a default 404.

## Example

The main file (`bin/main.dart`) below creates an engine with a standard route for `/hello` and a fallback route to handle all other requests.

```dart:examples/fallback%20route/bin/main.dart
import 'package:routed/routed.dart';

void main() {
  final engine = Engine.d();

  // Standard route: Returns a greeting when requested.
  engine.get('/hello', (ctx) => ctx.string('Hello World!'));

  // Fallback route: Catches all unmatched requests.
  engine.fallback((ctx) {
    ctx.string('This is the fallback handler');
  });

  engine.serve(port: 8080);
}
```