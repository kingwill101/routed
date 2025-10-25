import 'package:routed/routed.dart';

/// Classification for incoming Turbo-driven requests.
enum TurboRequestKind {
  /// Standard HTTP request without Turbo-specific headers.
  standard,

  /// Request originating from inside a `<turbo-frame>` block.
  frame,

  /// Request that expects Turbo Stream payloads.
  stream,
}

/// Parsed view of the headers Turbo adds to requests.
class TurboRequestInfo {
  TurboRequestInfo._(this.request, this._headers, this.method);

  /// Construct from a routed [request].
  factory TurboRequestInfo.fromRequest(Request request) {
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) {
      headers[name.toLowerCase()] = List.unmodifiable(values);
    });
    return TurboRequestInfo._(request, headers, request.method.toUpperCase());
  }

  /// Construct from a raw header map. Useful for tests or tooling.
  factory TurboRequestInfo.fromHeaders(
    Map<String, List<String>> headers, {
    String method = 'GET',
  }) {
    final normalized = <String, List<String>>{};
    headers.forEach((name, values) {
      normalized[name.toLowerCase()] = List.unmodifiable(values);
    });
    return TurboRequestInfo._(null, normalized, method.toUpperCase());
  }

  final Request? request;
  final Map<String, List<String>> _headers;
  final String method;

  static const _acceptHeader = 'accept';
  static const _turboStreamMime = 'text/vnd.turbo-stream.html';
  static const _requestIdHeader = 'x-turbo-request-id';

  /// Raw value for a header, if present.
  String? header(String name) {
    final values = _headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.join(', ');
  }

  /// Parsed Turbo Frame identifier (if the request originated from a frame).
  String? get frameId {
    final value = header('Turbo-Frame');
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Whether the request is a Turbo visit (Turbo Drive navigation/fetch).
  bool get isTurboVisit {
    final value = header('Turbo-Visit');
    return value != null && value.toLowerCase() == 'true';
  }

  /// Whether the request represents a Stream update (Accept header negotiation).
  bool get isStreamRequest =>
      _acceptValues().any((value) => value.contains(_turboStreamMime));

  /// The Turbo request identifier, if supplied via `X-Turbo-Request-Id`.
  String? get requestId {
    final value = header(_requestIdHeader);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// True when the request includes a `Turbo-Frame` header.
  bool get isFrameRequest => frameId != null;

  /// Shorthand classification for routing logic.
  TurboRequestKind get kind {
    if (isStreamRequest) return TurboRequestKind.stream;
    if (isFrameRequest) return TurboRequestKind.frame;
    return TurboRequestKind.standard;
  }

  /// Lists Accept header values (lowercased, trimmed).
  List<String> _acceptValues() {
    final raw = header(_acceptHeader);
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((part) => part.split(';').first.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}

const _turboInfoKey = '__routed_hotwire.turbo_request';

/// Convenient access to [TurboRequestInfo] on the routed [Request].
extension TurboRequestExtensions on Request {
  TurboRequestInfo get turbo {
    final cached = getAttribute<TurboRequestInfo>(_turboInfoKey);
    if (cached != null) return cached;
    final info = TurboRequestInfo.fromRequest(this);
    setAttribute(_turboInfoKey, info);
    return info;
  }
}

/// Shortcut for retrieving [TurboRequestInfo] directly from the context.
extension TurboContextExtensions on EngineContext {
  TurboRequestInfo get turbo {
    final cached = get<TurboRequestInfo>(_turboInfoKey);
    if (cached != null) return cached;
    final info = TurboRequestInfo.fromRequest(request);
    set(_turboInfoKey, info);
    _attachLoggingContext(this, info);
    return info;
  }
}

void _attachLoggingContext(EngineContext ctx, TurboRequestInfo info) {
  final additions = <String, Object?>{
    'hotwire.kind': info.kind.name,
    if (info.frameId != null) 'hotwire.frame_id': info.frameId,
    if (info.isStreamRequest) 'hotwire.stream_request': true,
    if (info.isTurboVisit) 'hotwire.visit': true,
    if (info.requestId != null) 'hotwire.request_id': info.requestId,
  };

  if (additions.isEmpty) {
    return;
  }

  ctx.logger.withContext({
    for (final entry in additions.entries) entry.key: entry.value,
  });

  final context = ctx.loggerContext;
  if (!identical(context, const {})) {
    context.addAll(additions);
  }
}
