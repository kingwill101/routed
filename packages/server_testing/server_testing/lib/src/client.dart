import 'package:server_testing/src/multipart_builder.dart';
import 'package:server_testing/src/response.dart';
import 'package:server_testing/src/transport/memory.dart';
import 'package:server_testing/src/transport/mode.dart';
import 'package:server_testing/src/transport/request_handler.dart';
import 'package:server_testing/src/transport/server.dart';
import 'package:server_testing/src/transport/transport.dart';

export 'response.dart';
export 'transport/mode.dart';

/// A client for testing HTTP endpoints with different transport modes.
///
/// This is the main entry point for testing HTTP-based applications. It provides
/// methods for sending HTTP requests and handling responses with a fluent API.
/// The client can operate in different transport modes, allowing tests to be run
/// either in-memory (for speed) or using real HTTP servers (for integration testing).
///
/// ## Basic Usage
///
/// ```dart
/// // Create a client with your request handler
/// final client = TestClient(yourRequestHandler);
///
/// // Send a GET request
/// final response = await client.get('/users');
///
/// // Make assertions on the response
/// response
///     .assertStatus(200)
///     .assertJsonPath('users.0.name', 'Alice');
/// ```
///
/// ## Transport Modes
///
/// The client supports two transport modes:
/// - [TransportMode.inMemory]: Requests are handled in memory without network I/O
/// - [TransportMode.ephemeralServer]: A real HTTP server is started for testing
///
/// ## Multipart Requests
///
/// For file uploads and form submissions, use the [multipart] method:
///
/// ```dart
/// final response = await client.multipart('/upload', (builder) {
///   builder.addField('description', 'Test file');
///   builder.addFileFromBytes(
///     name: 'file',
///     bytes: imageBytes,
///     filename: 'test.jpg',
///     contentType: MediaType('image', 'jpeg'),
///   );
/// });
/// ```
class TestClient {
  final TestTransport _transport;
  TransportOptions? _options;

  /// Factory constructor to create an instance of [TestClient].
  ///
  /// [handler] is the request handler that will process the HTTP requests.
  /// [mode] specifies the transport mode, defaulting to [TransportMode.inMemory].
  /// [options] provides additional configuration options for the transport.
  ///
  /// Example:
  /// ```dart
  /// // Create an in-memory client
  /// final client = TestClient(myHandler);
  ///
  /// // Create a client with a real HTTP server
  /// final serverClient = TestClient(
  ///   myHandler,
  ///   mode: TransportMode.ephemeralServer,
  /// );
  /// ```
  factory TestClient(
    RequestHandler handler, {
    TransportMode mode = TransportMode.inMemory,
    TransportOptions? options,
  }) {
    switch (mode) {
      case TransportMode.inMemory:
        return TestClient.inMemory(handler, options);
      case TransportMode.ephemeralServer:
        return TestClient.ephemeralServer(handler, options);
    }
  }

  /// Constructor for creating an in-memory transport client.
  ///
  /// This mode is faster and simpler for unit testing as it doesn't require
  /// network I/O. Requests are handled directly in memory.
  ///
  /// [handler] is the request handler that will process the HTTP requests.
  /// [options] provides additional configuration options for the transport.
  TestClient.inMemory(RequestHandler handler, [TransportOptions? options])
    : _transport = InMemoryTransport(handler),
      _options = options;

  /// Constructor for creating an ephemeral server transport client.
  ///
  /// This mode starts a real HTTP server for testing, which is useful for
  /// integration tests that need to verify the entire HTTP stack.
  ///
  /// [handler] is the request handler that will process the HTTP requests.
  /// [options] provides additional configuration options for the transport.
  TestClient.ephemeralServer(
    RequestHandler handler, [
    TransportOptions? options,
  ]) : _transport = ServerTransport(handler),
       _options = options;

  /// Sends a GET request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// // First implement a RequestHandler for your application
  /// class UserHandler implements RequestHandler {
  ///   @override
  ///   Future<void> handleRequest(HttpRequest request) async {
  ///     final response = request.response;
  ///     if (request.uri.path == '/users') {
  ///       response.statusCode = 200;
  ///       response.headers.contentType = ContentType.json;
  ///       response.write('{"users": [{"name": "Alice"}, {"name": "Bob"}]}');
  ///     } else {
  ///       response.statusCode = 404;
  ///     }
  ///     await response.close();
  ///   }
  ///
  ///   @override
  ///   Future<int> startServer({int port = 0}) async {
  ///     // Server implementation...
  ///     return port;
  ///   }
  ///
  ///   @override
  ///   Future<void> close([bool force = true]) async {
  ///     // Cleanup logic...
  ///   }
  /// }
  ///
  /// // Then in your test:
  /// final client = TestClient(UserHandler());
  /// final response = await client.get('/users');
  /// response.assertStatus(200);
  /// ```
  Future<TestResponse> get(String uri, {Map<String, List<String>>? headers}) {
    return _transport.sendRequest(
      'GET',
      uri,
      headers: headers,
      options: _options,
    );
  }

  /// Sends a GET request to the specified [uri] expecting a JSON response.
  ///
  /// This method sets the 'Accept' header to 'application/json'.
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.getJson('/users');
  /// response.assertJson((json) => json.has('users'));
  /// ```
  Future<TestResponse> getJson(
    String uri, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'GET',
      uri,
      headers: {
        ...?headers,
        'Accept': ['application/json'],
      },
      options: _options,
    );
  }

  /// Sends a POST request with a JSON body to the specified [uri].
  ///
  /// This method sets the 'Content-Type' header to 'application/json'.
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the JSON payload to be sent (can be a Map, List, or primitive value).
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.postJson('/users', {
  ///   'name': 'John Doe',
  ///   'email': 'john@example.com'
  /// });
  /// ```
  Future<TestResponse> postJson(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'POST',
      uri,
      headers: {
        ...?headers,
        'Content-Type': ['application/json'],
      },
      body: body,
      options: _options,
    );
  }

  /// Sends a PUT request with a JSON body to the specified [uri].
  ///
  /// This method sets the 'Content-Type' header to 'application/json'.
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the JSON payload to be sent (can be a Map, List, or primitive value).
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///

  /// Returns the resolved base URL when in ephemeral server mode.
  /// Starts the server if needed and returns `http://127.0.0.1:<port>`.
  Future<String> get baseUrlFuture async {
    if (_transport is ServerTransport) {
      final server = _transport;
      final port = server.portOrNull ?? await server.ensureServer();
      return 'http://127.0.0.1:$port';
    }
    return 'http://127.0.0.1';
  }

  /// Example:
  /// ```dart
  /// final response = await client.putJson('/users/1', {
  ///   'name': 'John Doe Updated',
  ///   'email': 'john.updated@example.com'
  /// });
  /// ```
  Future<TestResponse> putJson(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'PUT',
      uri,
      headers: {
        ...?headers,
        'Content-Type': ['application/json'],
      },
      body: body,
      options: _options,
    );
  }

  /// Sends a PATCH request with a JSON body to the specified [uri].
  ///
  /// This method sets the 'Content-Type' header to 'application/json'.
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the JSON payload to be sent (can be a Map, List, or primitive value).
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.patchJson('/users/1', {
  ///   'email': 'john.updated@example.com'
  /// });
  /// ```
  Future<TestResponse> patchJson(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'PATCH',
      uri,
      headers: {
        ...?headers,
        'Content-Type': ['application/json'],
      },
      body: body,
      options: _options,
    );
  }

  /// Sends a DELETE request to the specified [uri] expecting a JSON response.
  ///
  /// This method sets the 'Accept' header to 'application/json'.
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.deleteJson('/users/1');
  /// response.assertStatus(204);
  /// ```
  Future<TestResponse> deleteJson(
    String uri, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'DELETE',
      uri,
      headers: {
        ...?headers,
        'Accept': ['application/json'],
      },
      options: _options,
    );
  }

  /// Sends a POST request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.post('/users', 'name=John&email=john@example.com');
  /// response.assertStatus(201);
  /// ```
  Future<TestResponse> post(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'POST',
      uri,
      headers: headers,
      body: body,
      options: _options,
    );
  }

  /// Sends a HEAD request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.head('/users');
  /// response.assertStatus(200);
  /// ```
  Future<TestResponse> head(String uri, {Map<String, List<String>>? headers}) {
    return _transport.sendRequest(
      'HEAD',
      uri,
      headers: headers,
      options: _options,
    );
  }

  /// Sends an OPTIONS request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  /// [body] allows specifying an optional request payload.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.options('/preflight', headers: {
  ///   'Origin': ['https://client.dev'],
  ///   'Access-Control-Request-Method': ['POST'],
  /// });
  /// response.assertStatus(HttpStatus.noContent);
  /// ```
  Future<TestResponse> options(
    String uri, {
    Map<String, List<String>>? headers,
    dynamic body,
  }) {
    return _transport.sendRequest(
      'OPTIONS',
      uri,
      headers: headers,
      body: body,
      options: _options,
    );
  }

  /// Sends a PUT request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.put('/users/1', 'name=John&email=john@example.com');
  /// response.assertStatus(200);
  /// ```
  Future<TestResponse> put(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'PUT',
      uri,
      headers: headers,
      body: body,
      options: _options,
    );
  }

  /// Sends a PATCH request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.patch('/users/1', 'email=john.updated@example.com');
  /// response.assertStatus(200);
  /// ```
  Future<TestResponse> patch(
    String uri,
    dynamic body, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'PATCH',
      uri,
      headers: headers,
      body: body,
      options: _options,
    );
  }

  /// Sends a DELETE request to the specified [uri].
  ///
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.delete('/users/1');
  /// response.assertStatus(204);
  /// ```
  Future<TestResponse> delete(
    String uri, {
    Map<String, List<String>>? headers,
  }) {
    return _transport.sendRequest(
      'DELETE',
      uri,
      headers: headers,
      options: _options,
    );
  }

  /// Closes the transport client, releasing any resources.
  ///
  /// This should be called when the client is no longer needed.
  ///
  /// Example:
  /// ```dart
  /// await client.close();
  /// ```
  Future<void> close() => _transport.close();

  /// Sends a request with the specified [method] to the specified [uri].
  ///
  /// This is a lower-level method for sending custom HTTP requests.
  ///
  /// [method] is the HTTP method (e.g., 'GET', 'POST', 'PUT').
  /// [uri] is the endpoint to send the request to.
  /// [headers] is an optional parameter to provide additional headers.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  Future<TestResponse> request(
    String method,
    String uri, [
    Map<String, List<String>>? headers,
  ]) =>
      _transport.sendRequest(method, uri, headers: headers, options: _options);

  /// Sends a multipart POST request to the specified [path].
  ///
  /// This method is useful for testing file uploads and form submissions.
  ///
  /// [path] is the endpoint to send the request to.
  /// [builder] is a function to build the multipart request, allowing you to
  /// add fields and files to the request.
  ///
  /// Returns a [TestResponse] that can be used for assertions.
  ///
  /// Example:
  /// ```dart
  /// final response = await client.multipart('/upload', (builder) {
  ///   builder.addField('description', 'Test file');
  ///   builder.addFileFromBytes(
  ///     name: 'file',
  ///     bytes: [1, 2, 3, 4, 5],
  ///     filename: 'test.txt',
  ///     contentType: MediaType('text', 'plain'),
  ///   );
  /// });
  /// ```
  Future<TestResponse> multipart(
    String path,
    void Function(MultipartRequestBuilder) builder,
  ) async {
    final requestBuilder = MultipartRequestBuilder();

    builder(requestBuilder);

    final body = requestBuilder.buildBody();
    final header = requestBuilder.getHeaders();
    return await _transport.sendRequest(
      "POST",
      path,
      body: body,
      headers: header.map((key, value) => MapEntry(key, [value])),
      options: _options,
    );
  }
}
