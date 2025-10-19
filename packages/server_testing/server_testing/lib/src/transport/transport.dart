import 'dart:io';

import 'package:server_testing/server_testing.dart';

/// An abstract class that defines the transport mechanism for sending test requests.
/// Implementations of this class should handle the specifics of how requests are sent
/// and responses are received.
abstract class TestTransport {
  /// Sends a request with the specified [method] and [uri].
  ///
  /// The [method] parameter specifies the HTTP method to be used (e.g., 'GET', 'POST').
  /// The [uri] parameter specifies the endpoint to which the request is sent.
  ///
  /// Optional named parameters:
  /// - [headers]: A map of headers to include in the request. Each key is a header name,
  ///   and the corresponding value is a list of header values.
  /// - [body]: The body of the request, which can be of any type.
  /// - [options]: Additional transport options for the request.
  ///
  /// Returns a [Future] that completes with a [TestResponse] object containing the response
  /// data once the request is complete.
  Future<TestResponse> sendRequest(
    String method,
    String uri, {
    Map<String, List<String>>? headers,
    dynamic body,
    TransportOptions? options,
  });

  /// Closes the transport, releasing any resources that it holds.
  ///
  /// This method should be called when the transport is no longer needed to ensure
  /// that all resources are properly cleaned up.
  ///
  /// Returns a [Future] that completes once the transport has been closed.
  Future<void> close();
}

class TransportOptions {
  final InternetAddress? remoteAddress;
  final bool? keepAlive;
  final TransportMode mode;

  const TransportOptions({
    this.remoteAddress,
    this.keepAlive,
    this.mode = TransportMode.inMemory,
  });
}
