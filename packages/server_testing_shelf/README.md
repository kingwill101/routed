# server_testing_shelf

An adapter for the Shelf package to use server_testing for HTTP testing.

## Features

- 🔌 Seamlessly integrate Shelf applications with server_testing
- 🌐 Support for in-memory and real HTTP server testing
- 🔄 Automatic conversion between HttpRequest/HttpResponse and shelf Request/Response
- 🧪 Enables fluent testing API from server_testing with Shelf applications

## Installation

Add to your `pubspec.yaml`:

```yaml
dev_dependencies:
  server_testing_shelf: ^0.1.0
  server_testing: ^0.1.0
  test: ^1.24.0
```

## Usage

### Basic Example

```dart
import 'package:shelf/shelf.dart' as shelf;
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:test/test.dart';

void main() {
  // Create a shelf application
  final app = (shelf.Request request) {
    if (request.url.path == 'hello') {
      return Future.value(
        shelf.Response.ok(
          'Hello, World!',
          headers: {'content-type': 'text/plain'},
        ),
      );
    }
    return Future.value(shelf.Response.notFound('Not Found'));
  };

  // Wrap the app with ShelfRequestHandler
  final handler = ShelfRequestHandler(app);

  // Test with server_testing
  engineTest('GET /hello returns greeting', (client) async {
    final response = await client.get('/hello');
    
    response
      .assertStatus(200)
      .assertBodyContains('Hello, World!');
  }, handler: handler);
}
```

### JSON API Example

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart' as shelf;
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:test/test.dart';

void main() {
  // Create a JSON API with shelf
  final app = (shelf.Request request) {
    if (request.url.path == 'users') {
      return Future.value(
        shelf.Response.ok(
          jsonEncode({
            'users': [
              {'id': 1, 'name': 'Alice'},
              {'id': 2, 'name': 'Bob'},
            ]
          }),
          headers: {'content-type': 'application/json'},
        ),
      );
    }
    return Future.value(shelf.Response.notFound('Not Found'));
  };

  // Create the handler
  final handler = ShelfRequestHandler(app);

  // Test with server_testing
  engineTest('GET /users returns user list', (client) async {
    final response = await client.get('/users');
    
    response
      .assertStatus(200)
      .assertJson((json) {
        json.has('users')
            .count('users', 2)
            .whereNested('users.0.name', 'Alice');
      });
  }, handler: handler);
}
```

## Advanced Features

### Pipeline Integration

```dart
// Create a shelf pipeline with middleware
final pipeline = shelf.Pipeline()
    .addMiddleware(shelf.logRequests())
    .addMiddleware(corsHeaders())
    .addHandler(myRoutes);

// Test with server_testing
final handler = ShelfRequestHandler(pipeline);

engineTest('GET /api respects CORS', (client) async {
  final response = await client.get('/api');
  
  response
    .assertStatus(200)
    .assertHeader('Access-Control-Allow-Origin', '*');
});
```

### Testing with Real HTTP Server

```dart
engineTest('GET /data works with real HTTP server', (client) async {
  final response = await client.get('/data');
  
  response.assertStatus(200);
}, 
  handler: ShelfRequestHandler(myApp),
  transportMode: TransportMode.ephemeralServer,
);
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.