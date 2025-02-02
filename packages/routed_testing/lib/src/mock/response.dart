import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mockito/mockito.dart';
import 'package:routed_testing/src/mock.mocks.dart';
import 'package:routed_testing/src/mock/headers.dart';

/// Sets up a mock HTTP response with the given headers and body.
///
/// This function creates a [MockHttpResponse] instance and configures it with the
/// provided headers and body. It sets up the necessary mocks for the response's
/// status code, headers, and body handling methods.
///
/// The returned [MockHttpResponse] instance can be used in tests to simulate
/// an HTTP response.
///
/// Parameters:
/// - `headers`: An optional map of headers to set on the response.
/// - `body`: An optional [BytesBuilder] to capture the response body.
///
/// Returns:
/// The configured [MockHttpResponse] instance.
MockHttpResponse setupResponse(
    {Map<String, List<String>>? headers, BytesBuilder? body}) {
  final mockResponse = MockHttpResponse();
  final responseHeaders = <String, List<String>>{};
  body ??= BytesBuilder();
  int statusCode = HttpStatus.ok;
  final mockResponseHeaders = setupHeaders(headers ?? {});
  when(mockResponse.statusCode).thenReturn(statusCode);
  when(mockResponse.statusCode = any).thenAnswer((invocation) {
    statusCode = invocation.positionalArguments.first as int;
  });

  // Mock headers getter and setup headers
  when(mockResponse.headers).thenAnswer((i) => mockResponseHeaders);

  // Handle response headers
  // Capture headers added to response

  // Mock write and add methods to capture response body
  when(mockResponse.write(any)).thenAnswer((invocation) {
    final data = invocation.positionalArguments[0].toString();
    body?.add(utf8.encode(data));
  });

  // Inside InMemoryTransport class, in the sendRequest method:

  when(mockResponse.addStream(any)).thenAnswer((invocation) async {
    final stream = invocation.positionalArguments[0] as Stream<List<int>>;
    await for (final chunk in stream) {
      body?.add(chunk);
    }
  });

  when(mockResponse.add(any)).thenAnswer((invocation) {
    final data = invocation.positionalArguments[0] as List<int>;
    body?.add(data);
  });

  // Mock close method to finalize the response
  when(mockResponse.close()).thenAnswer((_) async {
    // No action needed for in-memory transport
  });
  // Build the TestResponse

  // Collect response headers
  final responseHeaderMap = <String, String>{};
  responseHeaders.forEach((key, values) {
    responseHeaderMap[key] = values.join(', ');
  });
  return mockResponse;
}
