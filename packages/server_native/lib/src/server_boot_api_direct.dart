part of 'server_boot.dart';

/// Request delivered to a direct FFI handler without `HttpRequest` wrapping.
///
/// {@macro server_native_transport_overview}
///
/// This request view avoids allocating `dart:io` HTTP wrappers and is useful
/// when handlers only need method/uri/header/body primitives.
final class NativeDirectRequest {
  /// Creates a request object from explicit fields.
  NativeDirectRequest({
    required String method,
    required String scheme,
    required String authority,
    required String path,
    required String query,
    required String protocol,
    required List<MapEntry<String, String>> headers,
    required this.body,
  }) : _frame = null,
       _payload = null,
       _method = method,
       _scheme = scheme,
       _authority = authority,
       _path = path,
       _query = query,
       _protocol = protocol,
       _headers = List<MapEntry<String, String>>.unmodifiable(headers);

  NativeDirectRequest._fromFrame(this._frame, this.body)
    : _payload = null,
      _method = null,
      _scheme = null,
      _authority = null,
      _path = null,
      _query = null,
      _protocol = null,
      _headers = null;

  NativeDirectRequest._fromPayload(this._payload, this.body)
    : _frame = null,
      _method = null,
      _scheme = null,
      _authority = null,
      _path = null,
      _query = null,
      _protocol = null,
      _headers = null;

  final BridgeRequestFrame? _frame;
  final _DirectPayloadRequestView? _payload;
  final String? _method;
  final String? _scheme;
  final String? _authority;
  final String? _path;
  final String? _query;
  final String? _protocol;
  List<MapEntry<String, String>>? _headers;

  /// Request body stream.
  final Stream<Uint8List> body;

  /// HTTP method (for example `GET`, `POST`).
  String get method => _frame?.method ?? _payload?.method ?? _method!;

  /// URL scheme (`http`, `https`, ...).
  String get scheme => _frame?.scheme ?? _payload?.scheme ?? _scheme!;

  /// Authority portion (`host[:port]`).
  String get authority =>
      _frame?.authority ?? _payload?.authority ?? _authority!;

  /// Request path (`/foo/bar`).
  String get path => _frame?.path ?? _payload?.path ?? _path!;

  /// Raw query string without leading `?`.
  String get query => _frame?.query ?? _payload?.query ?? _query!;

  /// HTTP protocol version string (`1.1`, `2`, ...).
  String get protocol => _frame?.protocol ?? _payload?.protocol ?? _protocol!;

  /// Header list preserving repeated values.
  List<MapEntry<String, String>> get headers {
    final headers = _headers;
    if (headers != null) {
      return headers;
    }
    final frame = _frame;
    if (frame == null) {
      final payload = _payload;
      if (payload == null) {
        return const <MapEntry<String, String>>[];
      }
      final view = UnmodifiableListView(payload.materializeHeaders());
      _headers = view;
      return view;
    }
    final view = UnmodifiableListView(_DirectHeaderListView(frame));
    _headers = view;
    return view;
  }

  /// Parsed request URI reconstructed from scheme/authority/path/query.
  late final Uri uri = _buildDirectUri(
    scheme: scheme,
    authority: authority,
    path: path,
    query: query,
  );

  /// Returns the first header value for [name], or `null`.
  ///
  /// Matching is ASCII case-insensitive.
  String? header(String name) {
    final frame = _frame;
    if (frame != null) {
      for (var i = 0; i < frame.headerCount; i++) {
        final headerName = frame.headerNameAt(i);
        if (identical(headerName, name) ||
            headerName == name ||
            _equalsAsciiIgnoreCase(headerName, name)) {
          return frame.headerValueAt(i);
        }
      }
      return null;
    }
    final payload = _payload;
    if (payload != null) {
      return payload.header(name);
    }

    final target = name;
    for (final entry in headers) {
      if (_equalsAsciiIgnoreCase(entry.key, target)) {
        return entry.value;
      }
    }
    return null;
  }
}

/// Response returned by [NativeDirectHandler].
///
/// {@macro server_native_direct_handler_example}
final class NativeDirectResponse {
  /// Creates an in-memory bytes response.
  NativeDirectResponse.bytes({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    Uint8List? bodyBytes,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = bodyBytes ?? Uint8List(0),
       body = null,
       encodedBridgePayload = null;

  /// Creates a streaming response.
  NativeDirectResponse.stream({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    required this.body,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = null,
       encodedBridgePayload = null;

  /// Returns a response backed by a pre-encoded bridge payload.
  ///
  /// This avoids per-request Dart response encoding when the same response can
  /// be reused (for example, static benchmark responses).
  NativeDirectResponse.encodedPayload({
    required Uint8List bridgeResponsePayload,
  }) : status = HttpStatus.ok,
       headers = const <MapEntry<String, String>>[],
       bodyBytes = null,
       body = null,
       encodedBridgePayload = bridgeResponsePayload {
    BridgeResponseFrame.decodePayload(bridgeResponsePayload);
  }

  /// Builds and caches a single encoded bridge response payload.
  factory NativeDirectResponse.preEncodedBytes({
    int status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    Uint8List? bodyBytes,
  }) {
    final frame = BridgeResponseFrame(
      status: status,
      headers: headers,
      bodyBytes: bodyBytes ?? Uint8List(0),
    );
    return NativeDirectResponse.encodedPayload(
      bridgeResponsePayload: frame.encodePayload(),
    );
  }

  /// Status code.
  final int status;

  /// Response headers.
  final List<MapEntry<String, String>> headers;

  /// Full response bytes for non-streaming responses.
  final Uint8List? bodyBytes;

  /// Streamed response body for streaming responses.
  final Stream<Uint8List>? body;

  /// Optional pre-encoded bridge response payload.
  final Uint8List? encodedBridgePayload;
}

/// Direct callback signature used by [serveNativeDirect] and
/// [serveSecureNativeDirect].
typedef NativeDirectHandler =
    FutureOr<NativeDirectResponse> Function(NativeDirectRequest request);
