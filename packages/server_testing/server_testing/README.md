# server_testing

A concise overview and links to topic guides.

Table of contents (see Docusaurus docs in this repo)

- Overview: docs/docs/testing/server-testing/intro.mdx
- Getting started: docs/docs/testing/server-testing/getting-started.mdx
- HTTP testing: docs/docs/testing/server-testing/http-testing.mdx
- Test client: docs/docs/testing/server-testing/test-client.mdx
- Test response: docs/docs/testing/server-testing/test-response.mdx
- Browser testing: docs/docs/testing/server-testing/browser-testing.mdx
- Browser config and devices: docs/docs/testing/server-testing/browser-config.mdx
- Pages and components: docs/docs/testing/server-testing/pages-and-components.mdx
- CLI (bundles and drivers): docs/docs/testing/server-testing/cli.mdx
- Handler providers (build your own): docs/docs/testing/server-testing/handler-providers.mdx

Quick start

```yaml
# pubspec.yaml (dev_dependencies)
server_testing: ^0.1.0
test: ^1.25.0
```

```bash
dart pub get
# optional browser bundle install
dart run server_testing install
```

For the full guides, see the docs/ directory.

- **Page & Component**: Base classes for page object pattern

## Advanced Features

### Custom Request Handlers

Implement your own request handlers for testing by creating a class that implements the `RequestHandler` interface.

#### Using the Built-in `IoRequestHandler`

For applications using `dart:io` `HttpServer` directly, use the built-in `IoRequestHandler`:

```dart
import 'dart:io';
import 'package:server_testing/server_testing.dart';

// Your existing request handler function
Future<void> handleRequest(HttpRequest request) async {
  final response = request.response;
  
  if (request.uri.path == '/ping') {
    response.statusCode = 200;
    response.write('pong');
  } else {
    response.statusCode = 404;
    response.write('Not found');
  }
  
  await response.close();
}

void main() {
  // Wrap your handler with IoRequestHandler
  final handler = IoRequestHandler(handleRequest);
  
  serverTest('GET /ping returns pong', (client) async {
    final response = await client.get('/ping');
    response.assertStatus(200).assertBodyEquals('pong');
  }, handler: handler);
}
```

#### Creating Custom Handlers

You can also create fully custom handlers:

```dart
import 'dart:io';
import 'package:server_testing/server_testing.dart';

class MyCustomHandler implements RequestHandler {
  @override
  Future<void> handleRequest(HttpRequest request) async {
    // Handle the request logic
    final response = request.response;
    response.statusCode = 200;
    response.headers.contentType = ContentType.json;
    response.write('{"status": "success"}');
    await response.close();
  }

  @override
  Future<int> startServer({int port = 0}) async {
    // Start a real server when using ephemeral server mode
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen(handleRequest);
    return server.port;
  }

  @override
  Future<void> close([bool force = true]) async {
    // Clean up resources
  }
}
```

#### Adapting Existing Web Frameworks

You can easily adapt existing web frameworks by creating handlers that delegate to your framework. For example, here's
how to adapt a hypothetical routing engine:

```dart
import 'dart:io';
import 'package:my_routing_framework/framework.dart';
import 'package:server_testing/server_testing.dart';

class RoutingFrameworkHandler implements RequestHandler {
  final Router router;
  HttpServer? _server;
  
  RoutingFrameworkHandler(this.router);
  
  @override
  Future<void> handleRequest(HttpRequest request) async {
    // Delegate the request to your router
    return router.handleRequest(request);
  }
  
  @override
  Future<int> startServer({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(handleRequest);
    return _server!.port;
  }
  
  @override
  Future<void> close([bool force = true]) async {
    await _server?.close(force: force);
    _server = null;
  }
}
```

This makes it simple to test applications built with any HTTP framework while taking advantage of server_testing's
assertion utilities.

### Page Object Pattern

Structure your browser tests using the page object pattern:

```dart
class LoginPage extends Page {
  LoginPage(super.browser);

  @override
  String get url => '/login';

  Future<void> login({required String email, required String password}) async {
    await browser.type('input[name="email"]', email);
    await browser.type('input[name="password"]', password);
    await browser.click('button[type="submit"]');
  }
}

// In your test
final loginPage = LoginPage(browser);
await loginPage.navigate();
await loginPage.login(email: 'test@example.com', password: 'password');
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for information on how to contribute to this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
