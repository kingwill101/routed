import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mockito/mockito.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/src/mock.mocks.dart';
import 'package:routed_testing/src/mock/headers.dart';
import 'package:routed_testing/src/mock/uri.dart';
import 'package:routed_testing/src/response.dart';
import 'package:routed_testing/src/transport/transport.dart';

/// InMemoryTransport is a class that implements the TestTransport interface.
/// It is used to simulate HTTP requests and responses in memory for testing purposes.
class InMemoryTransport implements TestTransport {
  /// The engine that handles the requests.
  final Engine _engine;

  /// Constructor for InMemoryTransport.
  /// Takes an [Engine] as a parameter.
  InMemoryTransport(this._engine);

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
  }) async {
    // Parse the URI
    final uriObj = setupUri(Uri.parse(uri));
    if (uriObj.path != uri) {
      when(uriObj.path).thenAnswer((c) => uri);
    }

    // Create new mock HttpRequest and HttpResponse for each request
    final mockRequest = MockHttpRequest();
    final mockResponse = MockHttpResponse();

    // Internal state for Request properties
    final requestHeaders = <String, List<String>>{
      ...headers ?? {},
    };
    final responseHeaders = <String, List<String>>{};
    final responseBody = BytesBuilder();

    final mockRequestHeaders = setupHeaders(requestHeaders);
    final mockResponseHeaders = setupHeaders(responseHeaders);

    // Set up mockRequest properties
    when(mockRequest.method).thenReturn(method);
    when(mockRequest.uri).thenReturn(uriObj);
    when(mockRequest.headers).thenReturn(mockRequestHeaders);

    // Handle contentLength
    if (body is Stream<List<int>>) {
      // For streams, set contentLength to -1 (unknown length)
      when(mockRequest.contentLength).thenReturn(-1);
    } else {
      // For non-stream bodies, calculate the length
      final bodyLength = body != null
          ? (body is String
              ? utf8.encode(body).length
              : (body is List<int>
                  ? body.length
                  : (body is Map || body is List
                      ? utf8.encode(jsonEncode(body)).length
                      : throw ArgumentError(
                          'Unsupported body type: ${body.runtimeType}'))))
          : 0;
      when(mockRequest.contentLength).thenReturn(bodyLength);
    }

    when(mockRequest.persistentConnection).thenReturn(true);
    when(mockRequest.response).thenReturn(mockResponse);

    // Handle multipart content type
    if (headers?['Content-Type']?.first.startsWith('multipart/form-data') ??
        false) {
      final contentType = ContentType.parse(headers!['Content-Type']!.first);
      mockRequest.headers.contentType = contentType;
    }

    // Mock the request stream to emit bodyBytes
    when(mockRequest.listen(
      any,
      onDone: anyNamed('onDone'),
      onError: anyNamed('onError'),
      cancelOnError: anyNamed('cancelOnError'),
    )).thenAnswer((invocation) {
      final onData =
          invocation.positionalArguments[0] as void Function(Uint8List)?;
      final onDone = invocation.namedArguments[#onDone] as void Function()?;
      // final onError = invocation.namedArguments[#onError] as void Function(Object)?;
      final cancelOnError = invocation.namedArguments[#cancelOnError] as bool?;

      StreamSubscription<Uint8List>? subscription;

      if (body is Stream<List<int>>) {
        // Handle streaming body
        subscription = body
            .map((chunk) =>
                Uint8List.fromList(chunk)) // Convert List<int> to Uint8List
            .listen(
          (chunk) {
            if (onData != null) onData(chunk);
          },
          onDone: onDone,
          // onError: onError != null ? (error) => onError(error) : null,
          cancelOnError: cancelOnError ?? false,
        );
      } else {
        // Handle non-streaming body
        Uint8List bodyBytes = Uint8List(0);
        if (body != null) {
          if (body is String) {
            bodyBytes = Uint8List.fromList(utf8.encode(body));
          } else if (body is List<int>) {
            bodyBytes = Uint8List.fromList(body);
          } else if (body is Map || body is List) {
            bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
          } else {
            throw ArgumentError('Unsupported body type: ${body.runtimeType}');
          }
        }

        // Emit the body bytes and then complete
        Future.microtask(() {
          if (onData != null) onData(bodyBytes);
          if (onDone != null) onDone();
        });
      }

      return subscription ?? Stream<Uint8List>.empty().listen(null);
    });

    // Set up mockResponse properties
    int statusCode = HttpStatus.ok;
    when(mockResponse.statusCode).thenReturn(statusCode);
    when(mockResponse.statusCode = any).thenAnswer((invocation) {
      statusCode = invocation.positionalArguments.first as int;
    });

    when(mockResponse.headers).thenAnswer((i) => mockResponseHeaders);

    when(mockResponse.write(any)).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0].toString();
      responseBody.add(utf8.encode(data));
    });

    when(mockResponse.addStream(any)).thenAnswer((invocation) async {
      final stream = invocation.positionalArguments[0] as Stream<List<int>>;
      await for (final chunk in stream) {
        responseBody.add(chunk);
      }
    });

    when(mockResponse.add(any)).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0] as List<int>;
      responseBody.add(data);
    });

    when(mockResponse.close()).thenAnswer((_) async {});

    // Handle the request with the engine
    await _engine.handleRequest(mockRequest);

    // Build the TestResponse
    final responseBodyBytes = responseBody.toBytes();
    final responseBodyString = utf8.decode(responseBodyBytes);

    // Collect response headers
    final responseHeaderMap = <String, String>{};
    responseHeaders.forEach((key, values) {
      responseHeaderMap[key] = values.join(', ');
    });

    return TestResponse(
      uri: uriObj.path,
      statusCode: statusCode,
      headers: responseHeaders,
      body: responseBodyString,
    );
  }

  @override
  Future<void> close() async {}
}
