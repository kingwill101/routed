import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:routed/routed.dart';
import 'package:routed_testing/src/response.dart';
import 'package:routed_testing/src/transport/transport.dart';

/// A class that implements the [TestTransport] interface to handle server transport.
class ServerTransport implements TestTransport {
  /// The engine instance used by the server.
  final Engine _engine;

  /// The HTTP server instance.
  HttpServer? _server;

  /// The port number on which the server is running.
  late int _port;

  /// The isolate instance for running the server.
  Isolate? _isolate;

  /// Constructor to initialize the [ServerTransport] with the given [Engine].
  ServerTransport(this._engine);

  /// Starts the server if it is not already running.
  Future<void> _maybeStartServer() async {
    if (_server == null) {
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(
          _serverRunner, _ServerConfig(_engine, receivePort.sendPort));
      _port = await receivePort.first;
    }
  }

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
  }) async {
    await _maybeStartServer();

    final client = HttpClient();
    final url = Uri.parse(uri);
    final resolvedUri =
        url.replace(port: _port, host: '127.0.0.1', scheme: "http");

    final request = await client.openUrl(method, resolvedUri);
    headers?.forEach((k, v) => request.headers.set(k, v));

    if (headers?['Content-Type']?.first.startsWith('multipart/form-data') ??
        false) {
      request.headers.contentType =
          ContentType.parse(headers!['Content-Type']!.first);
    }

    if (body != null) {
      if (body is Stream<List<int>>) {
        // Handle streaming body
        await request.addStream(body);
      } else if (body is List<int>) {
        // Handle byte array as a stream
        await request.addStream(Stream.value(body));
      } else if (request.headers.contentType?.mimeType == 'application/json') {
        // Handle JSON body
        request.write(jsonEncode(body));
      } else {
        // Handle other body types as a string
        request.write(body.toString());
      }
    }

    final response = await request.close();
    final rawData = await response
        .fold<List<int>>([], (prev, bytes) => prev..addAll(bytes));
    final rawBody = utf8.decode(rawData);

    var responseHeaders = <String, List<String>>{};
    response.headers.forEach((k, v) => responseHeaders[k] = v);

    return TestResponse(
      uri: uri,
      statusCode: response.statusCode,
      headers: responseHeaders,
      body: rawBody,
    );
  }

  /// Closes the server and kills the isolate.
  @override
  Future<void> close() async {
    _isolate?.kill();
    await _server?.close(force: true);
    _server = null;
  }
}

/// Configuration class for the server isolate.
class _ServerConfig {
  /// The engine instance used by the server.
  final Engine engine;

  /// The send port for communication with the isolate.
  final SendPort sendPort;

  /// Constructor to initialize the [_ServerConfig] with the given [Engine] and [SendPort].
  _ServerConfig(this.engine, this.sendPort);
}

/// The entry point for the server isolate.
///
/// [config] is the configuration for the server.
void _serverRunner(_ServerConfig config) async {
  final server = await HttpServer.bind('127.0.0.1', 0, shared: true);
  config.sendPort.send(server.port);
  await config.engine.serve(port: server.port);
}
