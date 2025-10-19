import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_testing/src/response.dart';
import 'package:server_testing/src/transport/request_handler.dart';
import 'package:server_testing/src/transport/transport.dart';

/// A class that implements the [TestTransport] interface to handle server transport.
class ServerTransport extends TestTransport {
  /// The engine instance used by the server.
  final RequestHandler _handler;

  /// The port number on which the server is running.
  late int _port;

  bool _started = false;

  /// Constructor to initialize the [ServerTransport] with the given [Engine].
  ServerTransport(this._handler);

  /// Starts the server if it is not already running.
  Future<void> _maybeStartServer() async {
    if (_started) return;
    _port = await _handler.startServer(port: 0);
    _started = true;
  }

  Future<int> ensureServer() async {
    await _maybeStartServer();
    return _port;
  }

  int? get portOrNull => _started ? _port : null;

  /// Sends an HTTP request to the server and returns the response.
  ///
  /// [method] is the HTTP method (e.g., GET, POST).
  /// [uri] is the URI of the request.
  /// [headers] are the optional headers to include in the request.
  /// [body] is the optional body of the request.
  ///
  /// Returns a [TestResponse] containing the response data.
  @override
  Future<TestResponse> sendRequest(
    String method,
    String uri, {
    Map<String, List<String>>? headers,
    dynamic body,
    TransportOptions? options,
  }) async {
    await _maybeStartServer();

    final client = HttpClient()..autoUncompress = false;
    final url = Uri.parse(uri);
    final resolvedUri = url.replace(
      port: _port,
      host: '127.0.0.1',
      scheme: "http",
    );

    final request = await client.openUrl(method, resolvedUri);
    headers?.forEach((key, values) {
      if (values.isEmpty) return;
      final headerValue = values.length == 1 ? values.first : values.join(', ');
      request.headers.set(key, headerValue);
    });

    if (headers?['Content-Type']?.first.startsWith('multipart/form-data') ??
        false) {
      request.headers.contentType = ContentType.parse(
        headers!['Content-Type']!.first,
      );
    }

    if (body != null) {
      if (body is Stream<List<int>>) {
        // Handle streaming body
        await request.addStream(body);
      } else if (body is List<int>) {
        // Handle byte array as a stream
        await request.addStream(Stream.value(body));
      } else if (request.headers.contentType?.mimeType == 'application/json') {
        // Handle JSON body, preserving raw strings
        if (body is String) {
          request.write(body);
        } else {
          request.write(jsonEncode(body));
        }
      } else if (body is String) {
        // Handle plain string body
        request.write(body);
      } else {
        // Handle other body types
        request.write(body.toString());
      }
    }

    final response = await request.close();
    final rawData = await response.fold<List<int>>(
      [],
      (prev, bytes) => prev..addAll(bytes),
    );
    var responseHeaders = <String, List<String>>{};
    response.headers.forEach((k, v) => responseHeaders[k] = v);

    return TestResponse(
      uri: uri,
      statusCode: response.statusCode,
      headers: responseHeaders,
      bodyBytes: rawData,
    );
  }

  /// Closes the server and kills the isolate.
  @override
  Future<void> close() async {
    _started = false;
    await _handler.close();
  }
}
