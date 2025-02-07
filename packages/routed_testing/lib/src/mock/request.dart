import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_testing/routed_testing.dart';
import 'package:routed_testing/src/mock.mocks.dart';

/// Sets up a mock HTTP request with the specified method and URI.
///
/// Creates and configures a [MockHttpRequest] with the given parameters:
/// - [method]: The HTTP method (GET, POST, etc.)
/// - [uri]: The request URI as a string
/// - [mockRequestHeaders]: Optional pre-configured mock headers
/// - [uriObj]: Optional pre-parsed URI object
/// - [requestHeaders]: Optional map of header names to values
/// - [body]: Optional request body (supports String, List<int>, Map, or List)
/// - [mockResponse]: Optional pre-configured mock response
///
/// The request is configured with:
/// - The specified method and URI
/// - Headers from [mockRequestHeaders] or [requestHeaders]
/// - Content length based on [body]
/// - Persistent connection set to true
/// - Response from [mockResponse]
///
/// For multipart requests, the content type header is properly parsed and set.
/// The body is encoded appropriately based on its type:
/// - String bodies are UTF-8 encoded
/// - List<int> bodies are used directly
/// - Map/List bodies are JSON encoded
///
/// Throws [ArgumentError] if the body type is not supported.
///
///
/// ```dart
/// final request = setupRequest('POST', '/api/data',
///   requestHeaders: {'Content-Type': ['application/json']},
///   body: {'id': 123}
/// );
/// ```
///
MockHttpRequest setupRequest(String method, String uri,
    {MockHttpHeaders? mockRequestHeaders,
    Uri? uriObj,
    Map<String, List<String>>? requestHeaders,
    List<Cookie>? cookies,
    dynamic body,
    MockHttpResponse? mockResponse,
    InternetAddress? remoteAddress}) {
  requestHeaders ??= {};

  // Add cookies to headers if provided
  if (cookies != null && cookies.isNotEmpty) {
    requestHeaders[HttpHeaders.cookieHeader] =
        cookies.map((cookie) => '${cookie.name}=${cookie.value}').toList();
  }

  //check if header has cookie header
  if (requestHeaders.containsKey(HttpHeaders.cookieHeader)) {
    final cookieHeader = requestHeaders[HttpHeaders.cookieHeader]!.first;
    //append to cookies variable
    cookies = [
      ...cookies ?? [],
      ...cookieHeader
          .split(',')
          .map((cookie) => Cookie.fromSetCookieValue(cookie))
    ];
  }

  mockRequestHeaders ??= setupHeaders(requestHeaders);

  final mockUri = setupUri(uri);

  final mockRequest = MockHttpRequest();

  // Setup cookies
  when(mockRequest.cookies).thenReturn(cookies ?? []);

  when(mockRequest.method).thenReturn(method);
  when(mockRequest.uri).thenReturn(mockUri);
  when(mockRequest.headers).thenReturn(mockRequestHeaders);
  when(mockRequest.contentLength).thenAnswer((c) {
    return body?.length ?? 0;
  });
  when(mockRequest.persistentConnection).thenReturn(true);

  mockResponse ??= MockHttpResponse();
  when(mockRequest.response).thenReturn(mockResponse);
  // Handle multipart content type
  if (requestHeaders['Content-Type']?.first.startsWith('multipart/form-data') ??
      false) {
    final contentType =
        ContentType.parse(requestHeaders['Content-Type']!.first);
    mockRequest.headers.contentType = contentType;
  }

// Mock body stream
  if (body != null) {
    // Prepare body bytes
    List<int> bodyBytes;
    if (body is String) {
      bodyBytes = utf8.encode(body);
    } else if (body is List<int>) {
      bodyBytes = body;
    } else if (body is Map || body is List) {
      bodyBytes = utf8.encode(jsonEncode(body));
    } else if (body is Stream<List<int>>) {
      // Handle Stream<List<int>> type
      when(mockRequest.listen(
        any,
        onDone: anyNamed('onDone'),
        onError: anyNamed('onError'),
        cancelOnError: anyNamed('cancelOnError'),
      )).thenAnswer((invocation) {
        final onData =
            invocation.positionalArguments[0] as void Function(List<int>)?;
        final onDone = invocation.namedArguments[#onDone] as void Function()?;
        final onError = invocation.namedArguments[#onError] as Function?;

        // Forward the stream events
        body.listen(
          (data) {
            if (onData != null) onData(data);
          },
          onDone: onDone,
          onError: onError,
        );

        return Stream<Uint8List>.empty().listen(null);
      });
      return mockRequest;
    } else {
      throw ArgumentError('Unsupported body type: ${body.runtimeType}');
    }

    // Mock body stream
    when(mockRequest.listen(
      any,
      onDone: anyNamed('onDone'),
      onError: anyNamed('onError'),
      cancelOnError: anyNamed('cancelOnError'),
    )).thenAnswer((invocation) {
      final onData =
          invocation.positionalArguments[0] as void Function(List<int>)?;
      final onDone = invocation.namedArguments[#onDone] as void Function()?;

      // Emit the body bytes and then complete
      Future.microtask(() {
        if (onData != null) onData(bodyBytes);
        if (onDone != null) onDone();
      });

      // Return a StreamSubscription that does nothing
      return Stream<Uint8List>.fromIterable([Uint8List.fromList(bodyBytes)])
          .listen(null);
    });
  } else {
    // Mock empty body
    when(mockRequest.listen(
      any,
      onDone: anyNamed('onDone'),
      onError: anyNamed('onError'),
      cancelOnError: anyNamed('cancelOnError'),
    )).thenAnswer((invocation) {
      final onDone = invocation.namedArguments[#onDone] as void Function()?;

      // Immediately complete without emitting data
      Future.microtask(() {
        if (onDone != null) onDone();
      });

      return Stream<Uint8List>.empty().listen(null);
    });
  }
  if (body != null) {
    // Prepare body bytes
    List<int> bodyBytes;
    if (body is String) {
      bodyBytes = utf8.encode(body);
    } else if (body is List<int>) {
      bodyBytes = body;
    } else if (body is Map || body is List) {
      bodyBytes = utf8.encode(jsonEncode(body));
    } else {
      throw ArgumentError('Unsupported body type: ${body.runtimeType}');
    }

    // Mock the request stream to emit bodyBytes
    when(mockRequest.listen(
      any,
      onDone: anyNamed('onDone'),
      onError: anyNamed('onError'),
      cancelOnError: anyNamed('cancelOnError'),
    )).thenAnswer((invocation) {
      final onData =
          invocation.positionalArguments[0] as void Function(List<int>)?;
      final onDone = invocation.namedArguments[#onDone] as void Function()?;

      // Emit the body bytes and then complete
      Future.microtask(() {
        if (onData != null) onData(bodyBytes);
        if (onDone != null) onDone();
      });

      // Return a StreamSubscription that does nothing
      return Stream<Uint8List>.fromIterable([Uint8List.fromList(bodyBytes)])
          .listen(null);
    });
  } else {
    // Mock empty body
    when(mockRequest.listen(
      any,
      onDone: anyNamed('onDone'),
      onError: anyNamed('onError'),
      cancelOnError: anyNamed('cancelOnError'),
    )).thenAnswer((invocation) {
      final onDone = invocation.namedArguments[#onDone] as void Function()?;

      // Immediately complete without emitting data
      Future.microtask(() {
        if (onDone != null) onDone();
      });

      return Stream<Uint8List>.empty().listen(null);
    });
  }

  // Mock connection info if remote address provided
  if (remoteAddress != null) {
    final mockConnectionInfo = MockHttpConnectionInfo();
    when(mockConnectionInfo.remoteAddress).thenReturn(remoteAddress);
    when(mockRequest.connectionInfo).thenReturn(mockConnectionInfo);
  }

  return mockRequest;
}
