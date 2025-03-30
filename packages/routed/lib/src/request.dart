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
  final HttpRequest httpRequest;

  /// A unique identifier for the request.
  final String id;

  /// A map to store request-scoped attributes.
  final Map<String, dynamic> _attributes;

  /// A map of path parameters extracted from the request URI.
  final Map<String, dynamic> pathParameters;

  /// A map of query parameters extracted from the request URI.
  final Map<String, String> queryParameters;

  /// Cached body bytes of the request.
  Uint8List? _bodyBytes;

  EngineConfig config;

  /// Constructs a [Request] object.
  ///
  /// The [httpRequest] parameter is the underlying HTTP request.
  /// The [pathParameters] parameter is a map of path parameters.
  Request(this.httpRequest, this.pathParameters, this.config)
      : queryParameters = _safeQueryParameters(httpRequest.uri),
        _attributes = {},
        id = RequestId.generate();

  /// Safely extracts query parameters from a URI, handling invalid encodings
  static Map<String, String> _safeQueryParameters(Uri uri) {
    try {
      return uri.queryParameters;
    } catch (e) {
      // Return empty map if query parameter parsing fails
      return <String, String>{};
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

  /// The [HttpResponse] object, used for sending back the response to the client.
  HttpResponse get response => httpRequest.response;

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
    if (!config.forwardedByClientIP) {
      return httpRequest.connectionInfo?.remoteAddress.address ?? '';
    }

    // Check if immediate client is trusted
    final remoteAddr = httpRequest.connectionInfo?.remoteAddress;
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

  /// Retrieves a request-scoped attribute by [key].
  ///
  /// Returns the attribute value if found, otherwise returns null.
  T? getAttribute<T>(String key) => _attributes[key] as T?;

  /// Sets a request-scoped attribute with the given [key] and [value].
  void setAttribute(String key, dynamic value) => _attributes[key] = value;

  /// Clears all request-scoped attributes.
  void clearAttributes() {
    _attributes.clear();
  }
}
