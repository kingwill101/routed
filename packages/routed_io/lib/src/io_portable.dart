import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// Converts a `dart:io` [HttpRequest] to a host-neutral [PortableRequest].
///
/// The method, URI, headers, remote address, and live request body are copied
/// into the portable value. The body remains single-consumer because it is the
/// original [HttpRequest] stream.
///
/// Use the result with [Engine.handlePortable] or [dispatchIoExchange]. For
/// WebSockets, progressive writes, or other native features, use
/// `IoHttpConnection` with [Engine.handleConnection] instead.
PortableRequest portableRequestFromIo(HttpRequest httpRequest) {
  final headers = PortableHeaders();
  httpRequest.headers.forEach((name, values) {
    headers.setAll(name, List<String>.from(values));
  });

  return PortableRequest(
    method: httpRequest.method,
    uri: httpRequest.uri,
    headers: headers,
    body: httpRequest,
    remoteAddress: httpRequest.connectionInfo?.remoteAddress.address,
  );
}

/// Writes a host-neutral [PortableResponse] to a `dart:io` [HttpResponse].
///
/// Status and headers are copied before the response body stream is consumed.
/// Repeated headers are preserved, including each `Set-Cookie` value, and the
/// target response is closed after all body chunks have been written.
///
/// Throws an error from the underlying response if the target has already been
/// closed or cannot accept more data.
Future<void> writePortableResponseToIo(
  PortableResponse source,
  HttpResponse target,
) async {
  target.statusCode = source.statusCode;
  source.headers.forEach((name, values) {
    if (name.toLowerCase() == HttpHeaders.setCookieHeader) {
      for (final value in values) {
        target.headers.add(name, value);
      }
    } else if (values.length == 1) {
      target.headers.set(name, values.first);
    } else {
      target.headers.set(name, values.join(', '));
    }
  });

  await for (final chunk in source.body) {
    if (chunk.isNotEmpty) target.add(chunk);
  }
  await target.close();
}

/// Dispatches one `dart:io` exchange through [Engine.handlePortable].
///
/// This creates a [PortableRequest], lets the engine produce a
/// [PortableResponse], and writes that value back to the request's response.
/// The value edge is useful for parity with Node and Workers-style hosts, but
/// buffers the response rather than providing the native streaming path.
///
/// `IoServerTransport` and `serveIo` use the native
/// [Engine.handleConnection] path by default so WebSockets and progressive
/// writes continue to work.
Future<void> dispatchIoExchange(Engine engine, HttpRequest httpRequest) async {
  final portableIn = portableRequestFromIo(httpRequest);
  final portableOut = await engine.handlePortable(portableIn);
  await writePortableResponseToIo(portableOut, httpRequest.response);
}
