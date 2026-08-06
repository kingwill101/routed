import 'dart:async';

import 'package:routed/src/engine/engine.dart' show Engine;

/// Minimal adapter exposed to portable domain packages and transports.
///
/// Each domain defines its own narrow adapter; this file provides the
/// foundation transport boundary so [Engine] can dispatch without
/// directly depending on `dart:io` in tests.
abstract interface class RequestAdapter {
  /// HTTP method, e.g. GET.
  String get method;

  /// Request URI.
  Uri get uri;

  /// Multi-value headers.
  Map<String, List<String>> get headers;

  /// Request body stream.
  Stream<List<int>> get body;

  /// Remote address if known.
  String? get remoteAddress;
}

/// Response adapter backed by the concrete server implementation.
abstract interface class ResponseAdapter {
  int get statusCode;
  set statusCode(int value);

  void setHeader(String name, String value);
  void addHeader(String name, String value);

  void write(List<int> bytes);
  Future<void> flush();
  Future<void> close();
}

/// Options passed to [ServerTransport.serve].
class ServerOptions {
  const ServerOptions({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.shared = false,
  });

  final String host;
  final int port;
  final bool shared;
}

/// Handle returned by a transport after binding.
abstract interface class ServerHandle {
  Future<void> close({bool force = false});
  String get host;
  int get port;
}

/// Pluggable server binding. The default Dart IO adapter lives inside [Engine];
/// alternate runtimes (e.g. `server_native`) implement this interface.
abstract interface class ServerTransport {
  Future<ServerHandle> serve(Engine engine, ServerOptions options);
}
