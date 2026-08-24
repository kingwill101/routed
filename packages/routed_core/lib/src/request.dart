import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/http/adapter_http.dart';
import 'package:routed_core/src/http/transport.dart';
import 'package:routed_core/src/utils/request_id.dart';

/// Represents an HTTP request and provides various utilities to access
/// request data and metadata.
class Request {
  /// The underlying native [HttpRequest] object.
  ///
  /// Portable requests do not expose a native request and throw
  /// [UnsupportedError] when this legacy accessor is used.
  @Deprecated('Use the request accessors instead of httpRequest directly.')
  HttpRequest get httpRequest {
    if (!hasNativeHttpRequest) {
      throw UnsupportedError(
        'Portable requests do not expose a native HttpRequest.',
      );
    }
    return _httpRequest;
  }

  final HttpRequest _httpRequest;

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
  Request(this._httpRequest, this.pathParameters, this.config)
    : queryParameters = _safeQueryParameters(_httpRequest.uri),
      _attributes = {},
      id = config.features.enableSecureRequestIds
          ? RequestId.generateSecure()
          : RequestId.generate(),
      startedAt = DateTime.now();

  /// Constructs a portable [Request] from a host adapter.
  factory Request.fromAdapter(
    RequestAdapter adapter,
    Map<String, dynamic> pathParameters,
    EngineConfig config,
  ) {
    return Request(
      AdapterHttpBridge.toHttpRequest(
        HttpConnection(adapter, _RequestBridgeResponseAdapter()),
      ),
      pathParameters,
      config,
    );
  }

  /// Whether this request is backed by a real native `dart:io` request.
  bool get hasNativeHttpRequest {
    final request = _httpRequest;
    if (request is SyntheticRequestCarrier) {
      return !(request as SyntheticRequestCarrier).isSyntheticRequest;
    }
    return request is! SyntheticHttpRequest;
  }

  /// Whether this request was built from a portable adapter.
  bool get isPortable => !hasNativeHttpRequest;

  /// Opaque host context supplied by a portable request adapter, when any.
  Object? get hostContext => _httpRequest is HostContextCarrier
      ? (_httpRequest as HostContextCarrier).hostContext
      : null;

  /// Stable object identity used by request-scoped `Expando` storage.
  Request get identity => this;

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
  String get method => _httpRequest.method;

  /// Returns the content length of the request body.
  int get contentLength => _httpRequest.contentLength;

  /// Returns the URI of the request.
  Uri get uri => _httpRequest.uri;

  /// Returns the requested URI for the request.
  Uri get requestedUri => _httpRequest.requestedUri;

  /// Returns the headers of the request.
  HttpHeaders get headers => _httpRequest.headers;

  /// Returns the cookies sent with the request.
  List<Cookie> get cookies => _httpRequest.cookies;

  /// Returns the persistent connection state signaled by the client.
  bool get persistentConnection => _httpRequest.persistentConnection;

  /// Returns the client certificate of the client making the request.
  X509Certificate? get certificate => _httpRequest.certificate;

  /// Returns the session for the given request.
  HttpSession get session => _httpRequest.session;

  /// Returns the HTTP protocol version used in the request, either "1.0" or "1.1".
  String get protocolVersion => _httpRequest.protocolVersion;

  /// Information about the client connection.
  HttpConnectionInfo? get connectionInfo => _httpRequest.connectionInfo;

  /// Returns the content type of the request, if available.
  ContentType? get contentType => _httpRequest.headers.contentType;

  /// Returns the path of the request URI.
  String get path => _httpRequest.uri.path;

  /// Returns the host of the request.
  String get host => _httpRequest.headers.host ?? '';

  /// Returns the scheme of the request URI (e.g., http, https).
  String get scheme => _httpRequest.uri.scheme;

  /// Returns the value of the specified header [name].
  String header(String name) => _httpRequest.headers[name]?.join(',') ?? '';

  /// Returns the remote address of the client making the request.
  String get remoteAddr =>
      _portableRemoteAddress ??
      _httpRequest.connectionInfo?.remoteAddress.address ??
      '';

  /// Returns the body of the request as a UTF-8 decoded string.
  FutureOr<String> body() async {
    return utf8.decode(await bytes);
  }

  /// Returns the body of the request as bytes.
  Future<Uint8List> get bytes async {
    if (_bodyBytes != null) return _bodyBytes!;
    _bodyConsumed = true;
    BytesBuilder bytes = BytesBuilder();
    await for (final chunk in _httpRequest) {
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
    final remoteAddr = _httpRequest.connectionInfo?.remoteAddress;
    final portableRemoteAddress = _portableRemoteAddress;
    final directAddress = portableRemoteAddress ?? remoteAddr?.address ?? '';
    if (!config.forwardedByClientIP || !config.features.enableProxySupport) {
      return directAddress;
    }

    final trustedProxy = remoteAddr != null
        ? config.isTrustedProxy(remoteAddr)
        : portableRemoteAddress != null &&
              config.isTrustedProxyText(portableRemoteAddress);
    if (!trustedProxy) {
      return directAddress;
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

    return directAddress;
  }

  String? get _portableRemoteAddress {
    final synthetic = _httpRequest;
    if (synthetic is PortableRemoteAddressCarrier) {
      return (synthetic as PortableRemoteAddressCarrier).portableRemoteAddress;
    }
    return null;
  }

  void overrideClientIp(String ip) {
    _overrideClientIp = ip;
  }

  /// Retrieves a request-scoped attribute by [key].
  ///
  /// Returns the attribute value if found and assignable to [T], otherwise
  /// returns null. A stored value of a different type (e.g. written through a
  /// legacy string key or a same-name key collision) is treated as absent
  /// instead of throwing a runtime type error.
  T? getAttribute<T>(String key) {
    final value = _attributes[key];
    if (value is T) return value;
    return null;
  }

  /// Returns `true` if an attribute with [key] is present, even when its
  /// value is `null` (e.g. written via [setAttribute]).
  bool containsAttribute(String key) => _attributes.containsKey(key);

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
      _BodyStreamWrapper(_httpRequest, onListen: () => _bodyConsumed = true);

  /// Returns whether the request body has been consumed.
  bool get bodyConsumed => _bodyConsumed;

  /// Returns whether the request has a body.
  ///
  /// For HTTP/1.1, a body is present when content-length > 0 or when
  /// transfer-encoding is chunked. If content-length is unknown and
  /// not chunked, treat it as no body to avoid hanging drains.
  bool get hasBody {
    final length = _httpRequest.contentLength;
    if (length > 0) return true;
    if (length == 0) return false;
    return _httpRequest.headers.chunkedTransferEncoding;
  }

  /// Drain the request body to allow keep-alive reuse when handlers
  /// don't read it. Safe to call multiple times.
  Future<void> drain() async {
    if (_bodyConsumed || !hasBody) return;
    _bodyConsumed = true;
    try {
      await _httpRequest.drain<void>();
    } catch (_) {
      // Ignore: request may already be listened to.
    }
  }
}

final class _RequestBridgeResponseAdapter implements ResponseAdapter {
  int _statusCode = 200;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) => _statusCode = value;

  @override
  void setHeader(String name, String value) {}

  @override
  void addHeader(String name, String value) {}

  @override
  void write(List<int> bytes) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
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
