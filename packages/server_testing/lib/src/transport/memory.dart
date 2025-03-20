import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/response.dart';
import 'package:server_testing/src/transport/transport.dart';

/// InMemoryTransport is a class that implements the TestTransport interface.
/// It is used to simulate HTTP requests and responses in memory for testing purposes.
class InMemoryTransport extends TestTransport {
  /// The engine that handles the requests.
  // final Engine _engine;

  final RequestHandler _handler;
  final Map<String, Cookie> _cookieStore = {};

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

    var responseHeaders =  headers ?? {};
    // Use setupResponse helper
    final mockResponse = setupResponse(headers: responseHeaders, body: responseBody);

    // Use setupRequest helper
    final mockRequest = setupRequest(
      method,
      uri,
      uriObj: uriObj,
      requestHeaders: headers,
      body: body,
      mockResponse: mockResponse,
      remoteAddress: options?.remoteAddress,
    );

    // Handle the request with the engine
    await _handler.handleRequest(mockRequest);

    // Build the TestResponse using the captured data
    final responseBodyBytes = responseBody.toBytes();
    final responseBodyString = utf8.decode(responseBodyBytes);

    final response = TestResponse(
      uri: uriObj.path,
      statusCode: mockResponse.statusCode,
      headers: mockResponse.headers.toMap(),
      body: responseBodyString,
    );

    final setCookies = response.headers[HttpHeaders.setCookieHeader] ?? [];
    for (final cookieStr in setCookies) {
      try {
        final cookie = Cookie.fromSetCookieValue(cookieStr);
        if (cookie.maxAge == 0) {
          _cookieStore.remove(cookie.name);
        } else {
          _cookieStore[cookie.name] = cookie;
        }
      } catch (e, s) {
        print("Error parsing cookie: $e");
        print('Stack trace: $s');
      }
    }
    return response;
  }

  @override
  Future<void> close() async {}
}
