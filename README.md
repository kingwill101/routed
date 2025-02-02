<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

# Routed

A fast, flexible HTTP router for Dart with support for middleware, template engines, and more.

## Features

- 🚀 Fast routing with path parameters and wildcards
- 🔌 Middleware support (timeout, logging, CORS)
- 🎨 Template engine support (Jinja and Liquid)
- 📁 Static file serving with directory listing
- 🍪 Cookie handling
- 🔄 Forward proxy support
- ⚡ Async request handling

## Quick Start

```dart
import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();
  
  // Basic routing
  engine.get('/hello/{name}', (ctx) {
    final name = ctx.param('name');
    ctx.string('Hello, $name!');
  });

  // JSON handling
  engine.post('/api/users', (ctx) async {
    final data = await ctx.request.body();
    ctx.json({'message': 'Created user', 'data': data});
  });

  await engine.serve(port: 8080);
}
```

## Examples

The `examples` directory contains working examples for common use cases:

- [Basic Router](examples/basic_router) - Path parameters, query strings, request body
- [Cookie Handling](examples/cookie_handling) - Setting and reading cookies
- [Forward Proxy](examples/forward_proxy) - Using as a proxy server
- [Jinja Template](examples/jinja_template) - Jinja templates with inheritance
- [Liquid Template](examples/liquid_template) - Liquid templates with partials
- [Route Parameters](examples/route_parameter_types) - Int, double, UUID, email parameters
- [Static File](examples/static_file) - File serving and directory listing
- [Timeout Middleware](examples/timeout_middleware) - Request timeouts

## Packages

- [routed](packages/routed) - Core routing package
- [routed_testing](packages/routed_testing) - Testing utilities

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
