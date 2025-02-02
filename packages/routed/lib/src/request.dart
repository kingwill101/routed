import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  /// Constructs a [Request] object.
  ///
  /// The [httpRequest] parameter is the underlying HTTP request.
  /// The [pathParameters] parameter is a map of path parameters.
  Request(this.httpRequest, this.pathParameters)
      : queryParameters = httpRequest.uri.queryParameters,
        _attributes = {},
        id = RequestId.generate();

  /// Returns the HTTP method of the request (e.g., GET, POST).
  String get method => httpRequest.method;

  /// Returns the content type of the request, if available.
  ContentType? get contentType => httpRequest.headers.contentType;

  /// Returns the path of the request URI.
  String get path => httpRequest.uri.path;

  /// Returns the host of the request.
  String get host => httpRequest.headers.host ?? '';

  /// Returns the scheme of the request URI (e.g., http, https).
  String get scheme => httpRequest.uri.scheme;

  /// Returns the value of the specified header [name].
  header(String name) => httpRequest.headers[name];

  /// Returns the headers of the request.
  HttpHeaders get headers => httpRequest.headers;

  /// Returns the remote address of the client making the request.
  String get remoteAddr =>
      httpRequest.connectionInfo?.remoteAddress.address ?? '';

  /// Returns the cookies sent with the request.
  List<Cookie> get cookies => httpRequest.cookies;

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

  /// Returns the URI of the request.
  Uri get uri => httpRequest.uri;

  /// Returns the IP address of the client making the request.
  ///
  /// This method checks for forwarded headers first (e.g., X-Forwarded-For,
  /// X-Real-IP) and falls back to the direct connection IP if no forwarded
  /// headers are found.
  String get ip {
    final forwardedFor = headers['X-Forwarded-For']?.firstOrNull;
    if (forwardedFor != null) {
      return forwardedFor.split(',').first.trim();
    }

    final realIp = headers['X-Real-IP']?.firstOrNull;
    if (realIp != null) {
      return realIp;
    }

    return remoteAddr;
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
