// Conditional request helpers per refactor.md §11.
import 'dart:convert';
import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// Result of evaluating the conditional request headers.
enum ConditionalOutcome {
  /// The request may continue normally.
  proceed,

  /// The resource has not changed and the response should be `304`.
  notModified,

  /// A request precondition failed and the response should be `412`.
  preconditionFailed,
}

/// A parsed entity tag from an HTTP conditional request header.
class EtagCandidate {
  /// Creates an entity-tag candidate.
  const EtagCandidate({this.value, this.weak = false, this.isWildcard = false});

  /// The tag value without surrounding quotes, if present.
  final String? value;

  /// Whether this candidate uses weak comparison semantics.
  final bool weak;

  /// Whether this candidate represents the `*` wildcard.
  final bool isWildcard;

  /// Whether a concrete tag value is available.
  bool get hasValue => value != null;
}

/// Parses the current entity tag from [value].
EtagCandidate? parseCurrentEtag(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return _parseEtag(value);
}

/// Parses comma-separated entity tags from [values].
List<EtagCandidate> parseEtagList(List<String> values) {
  final candidates = <EtagCandidate>[];
  for (final entry in values) {
    final segments = entry.split(',');
    for (final raw in segments) {
      final candidate = _parseEtag(raw);
      if (candidate != null) candidates.add(candidate);
    }
  }
  return candidates;
}

EtagCandidate? _parseEtag(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (value == '*') return const EtagCandidate(isWildcard: true);
  var weak = false;
  if (value.length > 2 && value.substring(0, 2).toLowerCase() == 'w/') {
    weak = true;
    value = value.substring(2).trim();
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  return EtagCandidate(value: value, weak: weak);
}

/// Compares [candidate] with the current entity tag.
bool etagMatches(
  EtagCandidate candidate,
  EtagCandidate current, {
  bool weakComparison = false,
}) {
  if (candidate.isWildcard) return true;
  if (candidate.value == null || current.value == null) return false;
  if (!weakComparison && (candidate.weak || current.weak)) return false;
  return candidate.value == current.value;
}

/// Evaluates the conditional headers on [ctx] against the supplied validators.
ConditionalOutcome evaluateConditional(
  EngineContext ctx, {
  String? etag,
  DateTime? lastModified,
}) {
  final ifMatch = ctx.requestHeader(HttpHeaders.ifMatchHeader);
  final ifNoneMatch = ctx.requestHeader(HttpHeaders.ifNoneMatchHeader);
  final ifModifiedSince = ctx.requestHeader(HttpHeaders.ifModifiedSinceHeader);
  final ifUnmodifiedSince = ctx.requestHeader(
    HttpHeaders.ifUnmodifiedSinceHeader,
  );
  // If-Match: if present and etag doesn't match -> preconditionFailed (412)
  if (ifMatch != null && etag != null) {
    final current = parseCurrentEtag(etag);
    if (current != null) {
      final candidates = parseEtagList([ifMatch]);
      var matched = false;
      for (final c in candidates) {
        if (etagMatches(c, current)) {
          matched = true;
          break;
        }
      }
      if (!matched) return ConditionalOutcome.preconditionFailed;
    }
  }
  if (ifUnmodifiedSince != null && lastModified != null) {
    try {
      final since = HttpDate.parse(ifUnmodifiedSince);
      if (lastModified.isAfter(since)) {
        return ConditionalOutcome.preconditionFailed;
      }
    } on FormatException catch (_) {}
  }
  if (ifNoneMatch != null && etag != null) {
    final current = parseCurrentEtag(etag);
    if (current != null) {
      final candidates = parseEtagList([ifNoneMatch]);
      for (final c in candidates) {
        if (etagMatches(c, current, weakComparison: true)) {
          return ConditionalOutcome.notModified;
        }
      }
    }
  }
  if (ifModifiedSince != null && lastModified != null) {
    try {
      final since = HttpDate.parse(ifModifiedSince);
      if (!lastModified.isAfter(since)) {
        return ConditionalOutcome.notModified;
      }
    } on FormatException catch (_) {}
  }
  return ConditionalOutcome.proceed;
}

/// Generates a base64 entity tag for [bytes].
String generateEtag(List<int> bytes, {bool weak = false}) {
  final digest = base64.encode(bytes);
  final value = '"$digest"';
  return weak ? 'W/$value' : value;
}

/// Creates middleware that handles HTTP conditional requests.
Middleware conditionalRequests({
  String? Function(EngineContext ctx)? etag,
  DateTime? Function(EngineContext ctx)? lastModified,
}) {
  return (EngineContext ctx, Next next) async {
    final etagVal = etag?.call(ctx);
    final lm = lastModified?.call(ctx);
    // Always set validators before evaluating so 304 responses include them
    if (etagVal != null) {
      ctx.response.headers.set(HttpHeaders.etagHeader, etagVal);
    }
    if (lm != null) {
      ctx.response.headers.set(
        HttpHeaders.lastModifiedHeader,
        HttpDate.format(lm),
      );
    }
    final outcome = evaluateConditional(ctx, etag: etagVal, lastModified: lm);
    if (outcome == ConditionalOutcome.notModified) {
      ctx.response.statusCode = HttpStatus.notModified;
      return ctx.response;
    }
    if (outcome == ConditionalOutcome.preconditionFailed) {
      ctx.response.statusCode = HttpStatus.preconditionFailed;
      return ctx.response;
    }
    return await next();
  };
}
