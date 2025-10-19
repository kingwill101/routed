import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_testing/server_testing.dart';

/// InMemoryTransport is a class that implements the TestTransport interface.
/// It is used to simulate HTTP requests and responses in memory for testing purposes.
class InMemoryTransport extends TestTransport {
  /// The engine that handles the requests.
  final RequestHandler _handler;
  final Map<String, Cookie> _cookieStore = {};

  // ignore: close_sinks
  MockHttpResponse? _mockResponse;

  /// Constructor for InMemoryTransport.
  /// Takes an [Engine] as a parameter.
  InMemoryTransport(this._handler);

  /// Sends an HTTP request and returns a [TestResponse].
  ///
  /// [method] is the HTTP method (e.g., GET, POST).
  /// [uri] is the URI of the request.
  /// [headers] are the optional HTTP headers.
  /// [body] is the optional body of the request.
  @override
  Future<TestResponse> sendRequest(
    String method,
    String uri, {
    Map<String, List<String>>? headers,
    dynamic body,
    TransportOptions? options,
  }) async {
    final uriObj = setupUri(uri);
    final responseBody = BytesBuilder();
    var responseHeaders = headers ?? {};

    final requestHeaders = <String, List<String>>{...?headers};
    if (_cookieStore.isNotEmpty) {
      requestHeaders[HttpHeaders.cookieHeader] = [
        _cookieStore.values
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; '),
      ];
    }

    // Use setupResponse helper
    _mockResponse = setupResponse(headers: responseHeaders, body: responseBody);

    // Use setupRequest helper
    final mockRequest = setupRequest(
      method,
      uri,
      uriObj: uriObj,
      requestHeaders: requestHeaders,
      cookies: _cookieStore.values.toList(),
      body: body,
      mockResponse: _mockResponse!,
      remoteAddress: options?.remoteAddress,
    );

    // Handle the request with the engine
    await _handler.handleRequest(mockRequest);

    // Build the TestResponse using the captured data
    final responseBodyBytes = responseBody.toBytes();
    final responseBodyString = utf8.decode(responseBodyBytes);

    // Build headers map from response only; avoid duplicating Set-Cookie
    final headersMap = _mockResponse!.headers.toMap();

    final response = TestResponse(
      uri: uriObj.path,
      statusCode: _mockResponse!.statusCode,
      headers: headersMap,
      bodyBytes: responseBodyBytes,
    );

    final setCookies =
        response.headers[HttpHeaders.setCookieHeader] ?? <String>[];
    for (final cookieStr in setCookies) {
      try {
        final cookie = Cookie.fromSetCookieValue(cookieStr);
        if (cookie.maxAge == 0) {
          _cookieStore.remove(cookie.name);
        } else {
          _cookieStore[cookie.name] = cookie;
        }
      } catch (_) {
        // Ignore malformed Set-Cookie lines
      }
    }

    return response;
  }

  @override
  Future<void> close() async {
    await _handler.close();
    // Do not close the last response again here; real servers don't re-close
    // responses when tearing down the client. This avoids state errors in tests.
    _mockResponse = null;
  }
}
