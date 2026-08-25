import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'package:routed_io/src/io_portable.dart';
import 'package:routed_io/src/io_request_adapter.dart';
import 'package:routed_io/src/io_response_adapter.dart';

/// A `dart:io` HTTP exchange containing its request and response.
///
/// This class exposes host-neutral [HttpConnection] adapters for
/// [Engine.handleConnection] while retaining the underlying `dart:io` types
/// for code that needs native request or response features.
///
/// Use [toPortableRequest] or [dispatchIoExchange] when the value-style
/// [PortableRequest] and [PortableResponse] boundary is preferred. The
/// portable request shares the request body stream and is therefore still
/// single-consumer.
final class IoHttpConnection {
  /// Creates a connection backed by [httpRequest].
  IoHttpConnection(this.httpRequest)
    : requestAdapter = IoRequestAdapter(httpRequest),
      responseAdapter = IoResponseAdapter(
        httpRequest.response,
        httpRequest: httpRequest,
      );

  /// The underlying `dart:io` request.
  final HttpRequest httpRequest;

  /// The response paired with [httpRequest].
  HttpResponse get httpResponse => httpRequest.response;

  /// The request adapter used by the host-neutral connection.
  ///
  /// This adapter also implements [NativeRequestHandle], so Routed can retain
  /// access to the native request on the default IO fast path.
  final IoRequestAdapter requestAdapter;

  /// The response adapter used by the host-neutral connection.
  final IoResponseAdapter responseAdapter;

  /// The host-neutral request and response pair for this exchange.
  HttpConnection get connection =>
      HttpConnection(requestAdapter, responseAdapter);

  /// Creates a host-neutral [PortableRequest] that shares the body stream.
  ///
  /// The returned request is single-consumer because its body is the live
  /// [HttpRequest] stream.
  PortableRequest toPortableRequest() => portableRequestFromIo(httpRequest);
}
