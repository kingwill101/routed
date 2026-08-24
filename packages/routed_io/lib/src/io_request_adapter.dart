import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// [RequestAdapter] backed by `dart:io` [HttpRequest].
final class IoRequestAdapter implements RequestAdapter, NativeRequestHandle {
  /// Creates a request adapter backed by [httpRequest].
  IoRequestAdapter(this.httpRequest);

  /// Underlying `dart:io` request.
  final HttpRequest httpRequest;

  @override
  Object? get nativeRequest => httpRequest;

  @override
  Object? get nativeResponse => httpRequest.response;

  @override
  String get method => httpRequest.method;

  @override
  Uri get uri => httpRequest.uri;

  @override
  Map<String, List<String>> get headers {
    final map = <String, List<String>>{};
    httpRequest.headers.forEach((name, values) {
      map[name] = List<String>.from(values);
    });
    return map;
  }

  @override
  Stream<List<int>> get body => httpRequest;

  @override
  String? get remoteAddress =>
      httpRequest.connectionInfo?.remoteAddress.address;
}
