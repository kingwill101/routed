import 'package:routed_core/routed_core.dart';

import 'package:routed_hotwire/src/turbo_streams.dart';

/// Helpers for sending Turbo-compatible responses from routed controllers.
class TurboResponse {
  const TurboResponse._();

  /// Send a full-page HTML response (Turbo Drive navigation).
  static Future<Response> html(
    EngineContext ctx,
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) async {
    return _write(ctx, html, 'text/html; charset=utf-8', statusCode, headers);
  }

  /// Send a fragment response scoped to a frame.
  static Future<Response> frame(
    EngineContext ctx,
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) async {
    return TurboResponse.html(
      ctx,
      html,
      statusCode: statusCode,
      headers: headers,
    );
  }

  /// Send a Turbo Stream payload with proper content type.
  static Future<Response> stream(
    EngineContext ctx,
    dynamic body, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) async {
    return _write(
      ctx,
      normalizeTurboStreamBody(body),
      'text/vnd.turbo-stream.html; charset=utf-8',
      statusCode,
      headers,
    );
  }

  /// Send a 422 response with HTML content (common for validation failures).
  static Future<Response> unprocessable(
    EngineContext ctx,
    String html, {
    Map<String, String>? headers,
  }) async {
    return _write(
      ctx,
      html,
      'text/html; charset=utf-8',
      HttpStatus.unprocessableEntity,
      headers,
    );
  }

  /// Issue a 303 redirect which Turbo Drive will follow automatically.
  static Future<Response> seeOther(
    EngineContext ctx,
    String location, {
    Map<String, String>? headers,
  }) async {
    if (ctx.isClosed) return ctx.string('');
    ctx
      ..status(HttpStatus.seeOther)
      ..setHeader(HttpHeaders.locationHeader, location);
    headers?.forEach(ctx.setHeader);
    await ctx.close();
    return ctx.string('');
  }

  static Future<Response> _write(
    EngineContext ctx,
    String body,
    String contentType,
    int statusCode,
    Map<String, String>? headers,
  ) async {
    if (ctx.isClosed) return ctx.string('');
    ctx
      ..status(statusCode)
      ..setHeader(HttpHeaders.contentTypeHeader, contentType);
    headers?.forEach(ctx.setHeader);
    ctx.write(body);
    await ctx.close();
    return ctx.string('');
  }
}

/// Mixin helpers onto [EngineContext] for concise usage.
extension TurboResponseContext on EngineContext {
  /// Sends a full-page HTML response.
  Future<Response> turboHtml(
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) =>
      TurboResponse.html(this, html, statusCode: statusCode, headers: headers);

  /// Sends an HTML response for a Turbo frame.
  Future<Response> turboFrame(
    String html, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) =>
      TurboResponse.frame(this, html, statusCode: statusCode, headers: headers);

  /// Sends a Turbo Stream response.
  Future<Response> turboStream(
    dynamic body, {
    int statusCode = HttpStatus.ok,
    Map<String, String>? headers,
  }) => TurboResponse.stream(
    this,
    body,
    statusCode: statusCode,
    headers: headers,
  );

  /// Issues a redirect that Turbo Drive follows automatically.
  Future<Response> turboSeeOther(
    String location, {
    Map<String, String>? headers,
  }) => TurboResponse.seeOther(this, location, headers: headers);

  /// Sends an HTML response with an unprocessable-entity status.
  Future<Response> turboUnprocessable(
    String html, {
    Map<String, String>? headers,
  }) => TurboResponse.unprocessable(this, html, headers: headers);
}
