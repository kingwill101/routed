import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// [ResponseAdapter] backed by `dart:io` [HttpResponse].
final class IoResponseAdapter implements ResponseAdapter, NativeRequestHandle {
  IoResponseAdapter(this.httpResponse, {this.httpRequest});

  /// Underlying `dart:io` response.
  final HttpResponse httpResponse;

  /// Optional paired request (same connection).
  final HttpRequest? httpRequest;

  @override
  Object? get nativeRequest => httpRequest;

  @override
  Object? get nativeResponse => httpResponse;

  @override
  int get statusCode => httpResponse.statusCode;

  @override
  set statusCode(int value) {
    httpResponse.statusCode = value;
  }

  @override
  void setHeader(String name, String value) {
    httpResponse.headers.set(name, value);
  }

  @override
  void addHeader(String name, String value) {
    httpResponse.headers.add(name, value);
  }

  @override
  void write(List<int> bytes) {
    httpResponse.add(bytes);
  }

  @override
  Future<void> flush() => httpResponse.flush();

  @override
  Future<void> close() => httpResponse.close();
}
