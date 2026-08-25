import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// A [RequestAdapter] backed by a `dart:io` [HttpRequest].
///
/// The adapter exposes the request through Routed's host-neutral contract and
/// also implements [NativeRequestHandle] for handlers that need the native
/// `dart:io` request on an IO host.
final class IoRequestAdapter implements RequestAdapter, NativeRequestHandle {
  /// Creates a request adapter backed by [httpRequest].
  IoRequestAdapter(this.httpRequest);

  /// The underlying `dart:io` request.
  final HttpRequest httpRequest;

  /// Returns the underlying [HttpRequest] for native host integrations.
  @override
  Object? get nativeRequest => httpRequest;

  /// Returns the response paired with [httpRequest].
  @override
  Object? get nativeResponse => httpRequest.response;

  /// Returns the HTTP method, such as `GET` or `POST`.
  @override
  String get method => httpRequest.method;

  /// Returns the absolute request URI supplied by `dart:io`.
  @override
  Uri get uri => httpRequest.uri;

  /// Returns a copy of the request headers and their values.
  @override
  Map<String, List<String>> get headers {
    final map = <String, List<String>>{};
    httpRequest.headers.forEach((name, values) {
      map[name] = List<String>.from(values);
    });
    return map;
  }

  /// Returns the live request body stream.
  ///
  /// The stream is single-consumer, matching the underlying [HttpRequest].
  @override
  Stream<List<int>> get body => httpRequest;

  /// Returns the peer IP address when connection information is available.
  @override
  String? get remoteAddress =>
      httpRequest.connectionInfo?.remoteAddress.address;
}
