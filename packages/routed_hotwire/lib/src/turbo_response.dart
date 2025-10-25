import 'package:routed/routed.dart';

import 'turbo_streams.dart';

/// Helpers for sending Turbo-compatible responses from routed controllers.
class TurboResponse {
  const TurboResponse._();

  /// Send a full-page HTML response (Turbo Drive navigation).
  static Response html(
    EngineContext ctx,
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) {
    return _write(ctx, html, 'text/html; charset=utf-8', statusCode, headers);
  }

  /// Send a fragment response scoped to a frame.
  static Response frame(
    EngineContext ctx,
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) {
    return TurboResponse.html(
      ctx,
      html,
      statusCode: statusCode,
      headers: headers,
    );
  }

  /// Send a Turbo Stream payload with proper content type.
  static Response stream(
    EngineContext ctx,
    dynamic body, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) {
    return _write(
      ctx,
      normalizeTurboStreamBody(body),
      'text/vnd.turbo-stream.html; charset=utf-8',
      statusCode,
      headers,
    );
  }

  /// Send a 422 response with HTML content (common for validation failures).
  static Response unprocessable(
    EngineContext ctx,
    String html, {
    Map<String, String>? headers,
  }) {
    return _write(
      ctx,
      html,
      'text/html; charset=utf-8',
      HttpStatus.unprocessableEntity,
      headers,
    );
  }

  /// Issue a 303 redirect which Turbo Drive will follow automatically.
  static Response seeOther(
    EngineContext ctx,
    String location, {
    Map<String, String>? headers,
  }) {
    final response = ctx.response;
    if (response.isClosed) return response;
    response.statusCode = HttpStatus.seeOther;
    response.setHeader(HttpHeaders.locationHeader, location);
    headers?.forEach(response.setHeader);
    response.close();
    return response;
  }

  static Response _write(
    EngineContext ctx,
    String body,
    String contentType,
    int statusCode,
    Map<String, String>? headers,
  ) {
    final response = ctx.response;
    if (response.isClosed) return response;
    response.statusCode = statusCode;
    response.setHeader(HttpHeaders.contentTypeHeader, contentType);
    headers?.forEach(response.setHeader);
    response.write(body);
    response.close();
    return response;
  }
}

/// Mixin helpers onto [EngineContext] for concise usage.
extension TurboResponseContext on EngineContext {
  Response turboHtml(
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) =>
      TurboResponse.html(this, html, statusCode: statusCode, headers: headers);

  Response turboFrame(
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) =>
      TurboResponse.frame(this, html, statusCode: statusCode, headers: headers);

  Response turboStream(
    dynamic body, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) => TurboResponse.stream(
    this,
    body,
    statusCode: statusCode,
    headers: headers,
  );

  Response turboSeeOther(String location, {Map<String, String>? headers}) =>
      TurboResponse.seeOther(this, location, headers: headers);

  Response turboUnprocessable(String html, {Map<String, String>? headers}) =>
      TurboResponse.unprocessable(this, html, headers: headers);
}
