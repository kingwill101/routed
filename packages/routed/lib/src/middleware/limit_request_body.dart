import 'dart:io';

import 'package:routed_security/routed_security.dart' as security;

import '../context/context.dart';
import '../router/types.dart';

/// Middleware that rejects requests whose body is larger than [maxBytes].
Middleware limitRequestBody(int maxBytes) {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be >= 0');
  }

  return (EngineContext ctx, Next next) async {
    final request = ctx.request;
    final exceedsLimit = security.exceedsRequestBodyLimit(
      maxBytes: maxBytes,
      headersContentLength: request.headers.contentLength,
      requestContentLength: request.contentLength,
      rawContentLength: request.headers.value(HttpHeaders.contentLengthHeader),
    );

    if (exceedsLimit) {
      return ctx.string(
        'Payload Too Large',
        statusCode: HttpStatus.requestEntityTooLarge,
      );
    }

    return await next();
  };
}
