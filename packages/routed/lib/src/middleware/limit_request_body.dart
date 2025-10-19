import 'dart:io';

import '../context/context.dart';
import '../router/types.dart';

/// Middleware that rejects requests whose body is larger than [maxBytes].
///
/// Behaviour:
/// 1. If the incoming request sends a `Content-Length` header and that value
///    exceeds [maxBytes], the middleware immediately responds with
///    `413 Payload Too Large`.
/// 2. If no `Content-Length` header is sent (e.g. chunked requests), the body
///    size cannot be determined up-front; therefore this middleware lets the
///    request continue.  You can combine this middleware with the
///    `timeoutMiddleware` to mitigate slow-loris attacks.
///
/// NOTE:
/// At the moment the middleware does **not** wrap the request’s stream to
/// perform incremental counting for chunked uploads because `EngineContext`
/// consumers in this package usually rely on `Content-Length` before reading
/// the stream.  This keeps the implementation small and free of breaking
/// changes.  If stream-level guarding is required, consider enhancing this
/// file with a `StreamTransformer` wrapper.
Middleware limitRequestBody(int maxBytes) {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be >= 0');
  }

  return (EngineContext ctx, Next next) async {
    final request = ctx.request;

    // Fast-fail if `Content-Length` is provided and exceeds the limit.
    var contentLength = request.headers.contentLength;
    if (contentLength == -1 || contentLength == 0) {
      contentLength = request.contentLength;
    }
    if (contentLength == -1 || contentLength == 0) {
      final headerValue = request.headers.value(
        HttpHeaders.contentLengthHeader,
      );
      if (headerValue != null) {
        contentLength = int.tryParse(headerValue) ?? -1;
      }
    }

    if (contentLength != -1 && contentLength > maxBytes) {
      return ctx.string(
        'Payload Too Large',
        statusCode: HttpStatus.requestEntityTooLarge,
      );
    }

    // No length header OR within limits.
    return await next();
  };
}
