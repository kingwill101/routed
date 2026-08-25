import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// A [ResponseAdapter] backed by a `dart:io` [HttpResponse].
///
/// The adapter translates Routed's host-neutral response operations into
/// native `dart:io` response operations. Pass [httpRequest] when the paired
/// native request should remain available through [NativeRequestHandle].
final class IoResponseAdapter implements ResponseAdapter, NativeRequestHandle {
  /// Creates a response adapter backed by [httpResponse].
  IoResponseAdapter(this.httpResponse, {this.httpRequest});

  /// The underlying `dart:io` response.
  final HttpResponse httpResponse;

  /// The optional request paired with [httpResponse].
  final HttpRequest? httpRequest;

  /// Returns the paired native request, if one was supplied.
  @override
  Object? get nativeRequest => httpRequest;

  /// Returns the underlying native response.
  @override
  Object? get nativeResponse => httpResponse;

  /// Returns the current HTTP status code.
  @override
  int get statusCode => httpResponse.statusCode;

  /// Sets the HTTP status code before the response is committed.
  @override
  set statusCode(int value) {
    httpResponse.statusCode = value;
  }

  /// Replaces all values for the response header named [name].
  @override
  void setHeader(String name, String value) {
    httpResponse.headers.set(name, value);
  }

  /// Adds [value] to the response header named [name].
  @override
  void addHeader(String name, String value) {
    httpResponse.headers.add(name, value);
  }

  /// Writes [bytes] to the response body.
  @override
  void write(List<int> bytes) {
    httpResponse.add(bytes);
  }

  /// Flushes buffered response bytes to the client.
  @override
  Future<void> flush() => httpResponse.flush();

  /// Closes the response and completes the exchange.
  @override
  Future<void> close() => httpResponse.close();
}
