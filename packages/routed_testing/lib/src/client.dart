import 'package:routed/routed.dart';
import 'package:routed_testing/src/multipart_builder.dart';
import 'package:routed_testing/src/response.dart';
import 'package:routed_testing/src/transport/memory.dart';
import 'package:routed_testing/src/transport/mode.dart';
import 'package:routed_testing/src/transport/server.dart';
import 'package:routed_testing/src/transport/transport.dart';
import 'package:http/http.dart' as http;
export 'transport/mode.dart';

/// A client for testing the Engine with different transport modes.
class EngineTestClient {
  final TestTransport _transport;

  /// Factory constructor to create an instance of [EngineTestClient].
  ///
  /// [engine] is an optional parameter to provide a custom [Engine] instance.
  /// [mode] specifies the transport mode, defaulting to [TransportMode.inMemory].
  factory EngineTestClient(
      [Engine? engine, TransportMode mode = TransportMode.inMemory]) {
    engine ??= Engine();
    switch (mode) {
      case TransportMode.inMemory:
        return EngineTestClient.inMemory(engine);
      case TransportMode.ephemeralServer:
        return EngineTestClient.ephemeralServer(engine);
    }
  }

  /// Constructor for creating an in-memory transport client.
  EngineTestClient.inMemory([Engine? engine])
      : _transport = InMemoryTransport(engine ?? Engine());

  /// Constructor for creating an ephemeral server transport client.
  EngineTestClient.ephemeralServer([Engine? engine])
      : _transport = ServerTransport(engine ?? Engine());

  /// Sends a GET request to the specified [uri].
  ///
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> get(String uri, {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('GET', uri, headers: headers);
  }

  /// Sends a GET request to the specified [uri] expecting a JSON response.
  ///
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> getJson(String uri,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('GET', uri, headers: {
      ...?headers,
      'Accept': ['application/json']
    });
  }

  /// Sends a POST request with a JSON body to the specified [uri].
  ///
  /// [body] is the JSON payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> postJson(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('POST', uri,
        headers: {
          ...?headers,
          'Content-Type': ['application/json']
        },
        body: body);
  }

  /// Sends a PUT request with a JSON body to the specified [uri].
  ///
  /// [body] is the JSON payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> putJson(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('PUT', uri,
        headers: {
          ...?headers,
          'Content-Type': ['application/json']
        },
        body: body);
  }

  /// Sends a PATCH request with a JSON body to the specified [uri].
  ///
  /// [body] is the JSON payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> patchJson(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('PATCH', uri,
        headers: {
          ...?headers,
          'Content-Type': ['application/json']
        },
        body: body);
  }

  /// Sends a DELETE request to the specified [uri] expecting a JSON response.
  ///
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> deleteJson(String uri,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('DELETE', uri, headers: {
      ...?headers,
      'Accept': ['application/json']
    });
  }

  /// Sends a POST request to the specified [uri].
  ///
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> post(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('POST', uri, headers: headers, body: body);
  }

  /// Sends a HEAD request to the specified [uri].
  ///
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> head(String uri, {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('HEAD', uri, headers: headers);
  }

  /// Sends a PUT request to the specified [uri].
  ///
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> put(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('PUT', uri, headers: headers, body: body);
  }

  /// Sends a PATCH request to the specified [uri].
  ///
  /// [body] is the payload to be sent.
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> patch(String uri, dynamic body,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('PATCH', uri, headers: headers, body: body);
  }

  /// Sends a DELETE request to the specified [uri].
  ///
  /// [headers] is an optional parameter to provide additional headers.
  Future<TestResponse> delete(String uri,
      {Map<String, List<String>>? headers}) {
    return _transport.sendRequest('DELETE', uri, headers: headers);
  }

  /// Closes the transport client.
  Future<void> close() => _transport.close();

  /// Sends a request with the specified [method] to the specified [uri].
  ///
  /// [headers] is an optional parameter to provide additional headers.
  request(String method, String s, [Map<String, List<String>>? headers]) =>
      _transport.sendRequest(method, s, headers: headers);

  /// Sends a multipart POST request to the specified [path].
  ///
  /// [builder] is a function to build the multipart request.
  Future<TestResponse> multipart(
      String path, void Function(MultipartRequestBuilder) builder) async {
    final requestBuilder = MultipartRequestBuilder();

    builder(requestBuilder);

    final body = requestBuilder.buildBody();
    final header = requestBuilder.getHeaders();
    return await _transport.sendRequest(
      "POST",
      path,
      body: body,
      headers: header.map((key, value) => MapEntry(key, [value])),
    );
  }
}
