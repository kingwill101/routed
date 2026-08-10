import 'dart:async';
import 'dart:io';

/// Minimal response/request surface needed to serve static files.
///
/// Framework adapters (e.g. `routed_storage`) implement this over their
/// request context so [FileHandler] stays free of framework imports.
abstract interface class StaticFileSink {
  /// HTTP method (GET, HEAD, …).
  String get method;

  /// Request headers.
  HttpHeaders get headers;

  /// Sets the response status code.
  set statusCode(int value);

  /// Sets a single response header (replacing prior values).
  void setHeader(String name, String value);

  /// Writes a string chunk to the response body.
  void write(String data);

  /// Streams binary data to the response body.
  Future<void> addStream(Stream<List<int>> stream);

  /// Completes the response.
  Future<void> close();

  /// Ends the response with [statusCode] and optional [message] body.
  void abortWithStatus(int statusCode, [String message = '']);

  /// Ends the response without writing a body (used for HEAD).
  void abort();
}
