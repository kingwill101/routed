# server_testing

A comprehensive testing utility package for Dart that provides fluent assertions for JSON and HTTP responses, browser
automation, and HTTP request/response mocking. Originally built to aid in testing the `routed` package, its core
utilities can be used independently in any Dart project.

## Features

### HTTP Testing

- 🌐 Flexible HTTP request/response testing via `EngineTestClient`
- 📝 Fluent response assertions with `TestResponse`
- 📦 Multipart request handling for file uploads
- 🔄 Multiple transport modes (in-memory and real HTTP server)

### Browser Testing

- 🌍 Cross-browser automated testing via WebDriver
- 🔌 Supports Chrome and Firefox
- 🤖 Browser automation with a fluent API
- 🧪 Page object pattern support
- 📱 Device emulation capabilities

### JSON Assertions

- 🔍 Fluent JSON assertions with `AssertableJson`
- 📊 Array and object validation
- 🔢 Type-safe numeric comparisons
- 🎯 Pattern matching and schema validation
- 🧩 Nested property navigation

### Mocking Utilities

- 🎭 HTTP request/response mocking
- 🔄 Cookie, session, and storage handling
- 📝 Header manipulation helpers

## Installation

Add to your `pubspec.yaml`:

```yaml
dev_dependencies:
  server_testing: ^0.1.0
  test: ^1.25.0
```

## Usage

### HTTP Testing with EngineTestClient

Use `EngineTestClient` to test your HTTP handlers with a fluent API:

```dart
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  // Define your request handler
  final handler = YourRequestHandler();

  engineTest('GET /users returns user list', (client) async {
    // Send a request
    final response = await client.get('/users');

    // Make assertions
    response
        .assertStatus(200)
        .assertJson((json) {
          json.has('users')
              .count('users', 3);
        });
  }, handler: handler);
}
```

### Browser Testing

Automate browser testing with the built-in browser testing utilities:

```dart
import 'package:server_testing/server_testing.dart';

void main() async {
  // Configure browser options
  final config = BrowserConfig(
    browserName: 'firefox',
    baseUrl: 'https://example.com',
    headless: false,
  );
  
  // Initialize browser environment
  await testBootstrap(config);
  
  // Run browser test
  await browserTest('guest can view homepage', (browser) async {
    // Navigate to a page
    await browser.visit('/');
    
    // Make assertions
    await browser.assertTitle('Example Domain');
    await browser.assertSee('This domain is for use in illustrative examples');
  }, config: config);
}
```

### Multipart Requests

Handle file uploads and form submissions with `multipart`:

```dart
final response = await client.multipart('/upload', (builder) {
// Add regular form fields
builder.addField('description', 'Test image');

// Add file content
builder.addFileFromBytes(
name: 'image',
bytes: imageBytes,
filename: 'test.png',
contentType: MediaType('image', 'png'),
);
});

response
    .assertStatus(200)
    .assertJson((json) {
json.has('success')
    .where('success', true);
});
```

### JSON Assertions

Make assertions on JSON data with a fluent API:

```dart
final json = AssertableJson({
  'user': {
    'name': 'Alice',
    'age': 28,
    'roles': ['admin', 'editor'],
    'settings': {
      'notifications': true
    }
  }
});

json.has('user')
    .hasNested('user.name')
    .whereNested('user.name', 'Alice')
    .isGreaterThanNested('user.age', 18)
    .countNested('user.roles', 2)
    .hasNested('user.settings.notifications');
```

## Architecture

The package is organized into several key components:

### Core Components

- **EngineTestClient**: The main entry point for HTTP testing
- **TestResponse**: Provides assertions on HTTP responses
- **AssertableJson**: Fluent assertions for JSON objects
- **Browser**: Interface for automated browser testing

### Transport Modes

- **InMemoryTransport**: Handles requests and responses in memory
- **ServerTransport**: Creates a real HTTP server for testing

### Browser Driver System

- **BrowserManager**: Handles browser installation and configuration
- **DriverManager**: Manages WebDriver instances for browser communication
- **Page & Component**: Base classes for page object pattern

## Advanced Features

### Custom Request Handlers

Implement your own request handlers for testing by creating a class that implements the `RequestHandler` interface:

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
