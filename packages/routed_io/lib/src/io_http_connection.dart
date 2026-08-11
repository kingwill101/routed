import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'io_portable.dart';
import 'io_request_adapter.dart';
import 'io_response_adapter.dart';

/// One `dart:io` HTTP exchange: holds both [HttpRequest] and [HttpResponse].
///
/// Exposes host-agnostic [HttpConnection] adapters for [Engine.handleConnection]
/// while keeping raw `dart:io` types available for advanced use.
///
/// For the value-style edge see [toPortableRequest] / [dispatchIoExchange].
final class IoHttpConnection {
  IoHttpConnection(this.httpRequest)
    : requestAdapter = IoRequestAdapter(httpRequest),
      responseAdapter = IoResponseAdapter(
        httpRequest.response,
        httpRequest: httpRequest,
      );

  /// Underlying `dart:io` request.
  final HttpRequest httpRequest;

  /// Underlying `dart:io` response.
  HttpResponse get httpResponse => httpRequest.response;

  /// Adapter request view (includes [NativeRequestHandle] for IO fast path).
  final IoRequestAdapter requestAdapter;

  /// Adapter response view.
  final IoResponseAdapter responseAdapter;

  /// Core-facing connection pair.
  HttpConnection get connection =>
      HttpConnection(requestAdapter, responseAdapter);

  /// Snapshot as a host-agnostic [PortableRequest] (shares the body stream).
  PortableRequest toPortableRequest() => portableRequestFromIo(httpRequest);
}
