import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// Maps a `dart:io` [HttpRequest] into a core [PortableRequest].
///
/// The body stream is the live [HttpRequest] (single-consumer). Prefer this
/// when using [Engine.handlePortable] / [dispatchIoExchange]. For websockets
/// and zero-copy native handling, use [IoHttpConnection] +
/// [Engine.handleConnection] instead.
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

/// Writes a core [PortableResponse] to a `dart:io` [HttpResponse].
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

/// Runs [engine.handlePortable] for one `dart:io` exchange.
///
/// Value edge (buffers the response via [RecordingResponseAdapter]). Use for
/// parity with Node/Workers-style hosts. Live [IoServerTransport] still uses
/// the native [Engine.handleConnection] fast path by default so websockets and
/// progressive writes keep working.
Future<void> dispatchIoExchange(Engine engine, HttpRequest httpRequest) async {
  final portableIn = portableRequestFromIo(httpRequest);
  final portableOut = await engine.handlePortable(portableIn);
  await writePortableResponseToIo(portableOut, httpRequest.response);
}
