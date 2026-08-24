import 'dart:io';

import 'package:routed_core/src/http/transport.dart';

/// Fields needed for route constraint / path matching without a full host request.
///
/// Lets routing validate domain and path params against portable adapters as well
/// as `dart:io` [HttpRequest].
abstract interface class ConstraintRequestView {
  /// HTTP method (e.g. GET).
  String get method;

  /// Request URI (path + query).
  Uri get uri;

  /// Host header value if present (no port required).
  String? get hostHeader;

  /// Native IO request when available (for `bool Function(HttpRequest)` constraints).
  ///
  /// Portable hosts return null; function constraints that need IO then fail closed.
  HttpRequest? get nativeHttpRequest;
}

/// [ConstraintRequestView] over `dart:io` [HttpRequest].
final class HttpConstraintView implements ConstraintRequestView {
  /// Creates a constraint view over [request].
  const HttpConstraintView(this.request);

  /// The native request being viewed.
  final HttpRequest request;

  @override
  String get method => request.method;

  @override
  Uri get uri => request.uri;

  @override
  String? get hostHeader => request.headers.host;

  @override
  HttpRequest? get nativeHttpRequest => request;
}

/// [ConstraintRequestView] over a portable [RequestAdapter].
final class AdapterConstraintView implements ConstraintRequestView {
  /// Creates a constraint view over [adapter].
  const AdapterConstraintView(this.adapter);

  /// The portable request adapter being viewed.
  final RequestAdapter adapter;

  @override
  String get method => adapter.method;

  @override
  Uri get uri => adapter.uri;

  @override
  String? get hostHeader {
    final values = adapter.headers['host'] ?? adapter.headers['Host'];
    if (values == null || values.isEmpty) return null;
    // Strip optional port for domain constraints.
    final raw = values.first;
    final colon = raw.lastIndexOf(':');
    if (colon > 0 && int.tryParse(raw.substring(colon + 1)) != null) {
      return raw.substring(0, colon);
    }
    return raw;
  }

  @override
  HttpRequest? get nativeHttpRequest => null;
}

/// Builds a [ConstraintRequestView] from common host types.
ConstraintRequestView constraintViewOf(Object request) {
  if (request is ConstraintRequestView) return request;
  if (request is HttpRequest) return HttpConstraintView(request);
  if (request is RequestAdapter) return AdapterConstraintView(request);
  throw ArgumentError.value(
    request,
    'request',
    'Expected HttpRequest, RequestAdapter, or ConstraintRequestView',
  );
}
