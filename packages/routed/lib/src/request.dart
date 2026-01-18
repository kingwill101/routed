import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed/src/engine/config.dart';
import 'package:routed/src/utils/request_id.dart';

/// Represents an HTTP request and provides various utilities to access
/// request data and metadata.
class Request {
  /// The underlying [HttpRequest] object.
  ///
  /// @deprecated Use the public API methods instead of accessing httpRequest directly.
  /// This field will be made private in a future version.
  final HttpRequest httpRequest;

  /// A unique identifier for the request.
  final String id;

  /// A map to store request-scoped attributes.
  final Map<String, dynamic> _attributes;

  /// A map of path parameters extracted from the request URI.
  final Map<String, dynamic> pathParameters;

  /// Timestamp indicating when the request handling began.
  final DateTime startedAt;

  /// A map of query parameters extracted from the request URI.
  final Map<String, String> queryParameters;

  /// Cached body bytes of the request.
  Uint8List? _bodyBytes;
  bool _bodyConsumed = false;

  EngineConfig config;
  String? _overrideClientIp;

  /// Constructs a [Request] object.
  ///
  /// The [httpRequest] parameter is the underlying HTTP request.
  /// The [pathParameters] parameter is a map of path parameters.
  Request(this.httpRequest, this.pathParameters, this.config)
    : queryParameters = _safeQueryParameters(httpRequest.uri),
      _attributes = {},
      id = config.features.enableSecureRequestIds
          ? RequestId.generateSecure()
          : RequestId.generate(),
      startedAt = DateTime.now();

  /// Safely extracts query parameters from a URI, handling invalid encodings
  static Map<String, String> _safeQueryParameters(Uri uri) {
    try {
      return uri.queryParameters;
    } catch (e) {
      // Return empty map if query parameter parsing fails
      return const <String, String>{};
    }
  }

  /// Returns the HTTP method of the request (e.g., GET, POST).
  String get method => httpRequest.method;

  /// Returns the content length of the request body.
  int get contentLength => httpRequest.contentLength;

  /// Returns the URI of the request.
  Uri get uri => httpRequest.uri;

  /// Returns the requested URI for the request.
  Uri get requestedUri => httpRequest.requestedUri;

  /// Returns the headers of the request.
  HttpHeaders get headers => httpRequest.headers;

  /// Returns the cookies sent with the request.
  List<Cookie> get cookies => httpRequest.cookies;

  /// Returns the persistent connection state signaled by the client.
  bool get persistentConnection => httpRequest.persistentConnection;

  /// Returns the client certificate of the client making the request.
  X509Certificate? get certificate => httpRequest.certificate;

  /// Returns the session for the given request.
  HttpSession get session => httpRequest.session;

  /// Returns the HTTP protocol version used in the request, either "1.0" or "1.1".
  String get protocolVersion => httpRequest.protocolVersion;

  /// Information about the client connection.
  HttpConnectionInfo? get connectionInfo => httpRequest.connectionInfo;

  /// Returns the content type of the request, if available.
  ContentType? get contentType => httpRequest.headers.contentType;

  /// Returns the path of the request URI.
  String get path => httpRequest.uri.path;

  /// Returns the host of the request.
  String get host => httpRequest.headers.host ?? '';

  /// Returns the scheme of the request URI (e.g., http, https).
  String get scheme => httpRequest.uri.scheme;

  /// Returns the value of the specified header [name].
  String header(String name) => httpRequest.headers[name]?.join(',') ?? '';

  /// Returns the remote address of the client making the request.
  String get remoteAddr =>
      httpRequest.connectionInfo?.remoteAddress.address ?? '';

  /// Returns the body of the request as a UTF-8 decoded string.
  FutureOr<String> body() async {
    return utf8.decode(await bytes);
  }

  /// Returns the body of the request as bytes.
  Future<Uint8List> get bytes async {
    if (_bodyBytes != null) return _bodyBytes!;
    _bodyConsumed = true;
    BytesBuilder bytes = BytesBuilder();
    await for (final chunk in httpRequest) {
      bytes.add(chunk);
    }
    _bodyBytes = bytes.toBytes();
    return _bodyBytes!;
  }

  /// Returns the IP address of the client making the request.
  ///
  /// This method checks for forwarded headers and trusted proxies based on the
  /// engine configuration. It falls back to the direct connection IP if no
  /// forwarded headers are found or if the immediate client is not trusted.
  String get clientIP {
    if (_overrideClientIp != null) {
      return _overrideClientIp!;
    }
    final remoteAddr = httpRequest.connectionInfo?.remoteAddress;
    if (!config.forwardedByClientIP || !config.features.enableProxySupport) {
      return remoteAddr?.address ?? '';
    }

    if (remoteAddr == null || !config.isTrustedProxy(remoteAddr)) {
      return remoteAddr?.address ?? '';
    }

    // Check platform-specific header first
    if (config.trustedPlatform != null) {
      final platformIP = headers[config.trustedPlatform!]?.first;
      if (platformIP != null) return platformIP;
    }

    // Check forwarded headers in order of priority
    for (final header in config.remoteIPHeaders) {
      final values = headers[header];
      if (values != null && values.isNotEmpty) {
        return values.first.split(',')[0].trim();
      }
    }

    return remoteAddr.address;
  }

  void overrideClientIp(String ip) {
    _overrideClientIp = ip;
  }

  /// Retrieves a request-scoped attribute by [key].
  ///
  /// Returns the attribute value if found, otherwise returns null.
  T? getAttribute<T>(String key) => _attributes[key] as T?;

  /// Sets a request-scoped attribute with the given [key] and [value].
  /// Store a value [value] under [key].
  void setAttribute(String key, dynamic value) => _attributes[key] = value;

  /// Clears all request-scoped attributes.
  void clearAttributes() {
    _attributes.clear();
  }

  /// Returns a stream of the request body data.
  ///
  /// This allows consuming the request body as a stream without directly
  /// accessing the underlying HttpRequest object.
  Stream<List<int>> get stream =>
      _BodyStreamWrapper(httpRequest, onListen: () => _bodyConsumed = true);

  /// Returns whether the request body has been consumed.
  bool get bodyConsumed => _bodyConsumed;

  /// Returns whether the request has a body.
  ///
  /// For HTTP/1.1, a body is present when content-length > 0 or when
  /// transfer-encoding is chunked. If content-length is unknown and
  /// not chunked, treat it as no body to avoid hanging drains.
  bool get hasBody {
    final length = httpRequest.contentLength;
    if (length > 0) return true;
    if (length == 0) return false;
    return httpRequest.headers.chunkedTransferEncoding;
  }

  /// Drain the request body to allow keep-alive reuse when handlers
  /// don't read it. Safe to call multiple times.
  Future<void> drain() async {
    if (_bodyConsumed || !hasBody) return;
    _bodyConsumed = true;
    try {
      await httpRequest.drain<void>();
    } catch (_) {
      // Ignore: request may already be listened to.
    }
  }
}

class _BodyStreamWrapper extends Stream<List<int>> {
  _BodyStreamWrapper(this._source, {required this.onListen});

  final Stream<List<int>> _source;
  final void Function() onListen;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onListen();
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
