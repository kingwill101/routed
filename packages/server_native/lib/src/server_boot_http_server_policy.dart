part of 'server_boot.dart';

/// Applies runtime request policies before dispatching to `HttpServer` listeners.
///
/// This mirrors common `dart:io` behavior:
/// - session is lazily resolved with [sessionTimeoutSeconds]
/// - transparent gzip compression follows server and request capabilities
/// - default response headers are copied to each response before user writes
void _applyNativeHttpRequestPolicies({
  required BridgeHttpRequest request,
  required _NativeSessionStore sessions,
  required int sessionTimeoutSeconds,
  required bool autoCompress,
  required HttpHeaders defaultResponseHeaders,
  required String? serverHeader,
}) {
  request.setSessionFactory(
    () => sessions.resolve(
      request: request,
      response: request.response,
      timeout: Duration(seconds: sessionTimeoutSeconds),
    ),
  );

  final requestAcceptsGzip = _acceptsGzip(request);
  final response = request.response;
  if (response case BridgeHttpResponse()) {
    response.configureAutoCompression(
      enabled: autoCompress,
      requestAcceptsGzip: requestAcceptsGzip,
    );
  } else if (response case BridgeStreamingHttpResponse()) {
    response.configureAutoCompression(
      enabled: autoCompress,
      requestAcceptsGzip: requestAcceptsGzip,
    );
  }

  final responseHeaders = request.response.headers;
  defaultResponseHeaders.forEach((name, values) {
    responseHeaders.removeAll(name);
    for (final value in values) {
      responseHeaders.add(name, value);
    }
  });
  if (serverHeader != null) {
    responseHeaders.set(HttpHeaders.serverHeader, serverHeader);
  }
}
