import 'dart:async';
import 'dart:io';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/http/conditional.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart' show Middleware, Next;

typedef EtagResolver = FutureOr<String?> Function(EngineContext ctx);
typedef LastModifiedResolver = FutureOr<DateTime?> Function(EngineContext ctx);

/// Middleware that evaluates HTTP conditional request headers and short-circuits
/// responses with 304 (Not Modified) or 412 (Precondition Failed) where appropriate.
Middleware conditionalRequests({
  EtagResolver? etag,
  LastModifiedResolver? lastModified,
}) {
  return (EngineContext ctx, Next next) async {
    final method = ctx.request.method.toUpperCase();
    final resolvedEtag = etag != null
        ? await Future.sync(() => etag(ctx))
        : null;
    final resolvedLastModified = lastModified != null
        ? await Future.sync(() => lastModified(ctx))
        : null;

    final outcome = evaluateConditionals(
      method: method,
      headers: ctx.request.headers,
      etag: resolvedEtag,
      lastModified: resolvedLastModified,
    );

    if (outcome == ConditionalOutcome.notModified) {
      _applyValidators(ctx.response, resolvedEtag, resolvedLastModified);
      ctx.response.statusCode = HttpStatus.notModified;
      return ctx.response;
    }

    if (outcome == ConditionalOutcome.preconditionFailed) {
      _applyValidators(ctx.response, resolvedEtag, resolvedLastModified);
      ctx.response.statusCode = HttpStatus.preconditionFailed;
      return ctx.response;
    }

    final result = await next();
    _applyValidators(ctx.response, resolvedEtag, resolvedLastModified);
    return result;
  };
}

void _applyValidators(Response response, String? etag, DateTime? lastModified) {
  if (etag != null && etag.isNotEmpty) {
    response.headers.set(HttpHeaders.etagHeader, etag);
  }
  if (lastModified != null) {
    response.headers.set(
      HttpHeaders.lastModifiedHeader,
      HttpDate.format(_truncateToSeconds(lastModified.toUtc())),
    );
  }
}

DateTime _truncateToSeconds(DateTime value) {
  return DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );
}
