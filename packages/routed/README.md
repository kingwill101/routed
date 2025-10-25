# routed

Routed is a modular HTTP engine for Dart that blends routing, middleware, and configuration into a single cohesive framework. It powers the rest of the routed ecosystem and ships with batteries included for sessions, caching, storage, observability, and authentication.

## Features
- Declarative router with middleware, guards, and rich request/response helpers
- Pluggable engine providers for configuration, observability, caching, uploads, and more
- Session, JWT, and OAuth2 helpers built on the same primitives
- First-class testing support via the `routed_testing` and `server_testing` packages
- Hotwire/Turbo helpers and class-based views available through companion packages

## Installation
Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  routed: ^0.1.0
```

Then run `dart pub get` to install the dependency.

## Getting started
Create an engine, register routes, and start handling requests:

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = Engine();

  engine.get('/hello', (ctx) => ctx.string('Hello, world!'));

  await engine.serve(address: 'localhost', port: 8080);
}
```

See the examples in the `example/` directory for more advanced scenarios including middleware, dependency injection, and WebSocket support.

## License
This project is licensed under the MIT License. See the `LICENSE` file for details.
