import 'dart:io';

import 'package:mockito/mockito.dart';
import 'package:routed_testing/src/mock.mocks.dart';

/// Sets up mock HTTP headers with the given request headers map.
///
/// Takes a [Map<String, List<String>>] of request headers and configures a mock
/// [HttpHeaders] instance to handle common header operations including:
///
/// * Setting/getting content length
/// * Setting/getting content type
/// * Getting header values by name
/// * Iterating over headers
/// * Adding header values
/// * Setting header values
///
/// Returns a [MockHttpHeaders] instance configured with the provided request headers.
/// The mock headers will maintain state in the provided headers map.
///
///
/// final headers = <String, List<String>>{};
/// final mockHeaders = setupHeaders(headers);
/// mockHeaders.contentType = ContentType.json;
/// print(headers['content-type']); // ['application', 'json']
///
///
/// This is primarily used for testing HTTP request/response handling.

MockHttpHeaders setupHeaders(Map<String, List<String>> requestHeaders) {
  final mockRequestHeaders = MockHttpHeaders();
  ContentType? contentType;

  for (final entry in requestHeaders.entries) {
    if (entry.key.toLowerCase() == HttpHeaders.contentTypeHeader) {
      contentType = ContentType.parse(entry.value.join(", "));
    }
  }

  when(mockRequestHeaders.contentLength = any).thenAnswer((invocation) {
    final contentLength = invocation.positionalArguments[0] as int;
    requestHeaders
        .putIfAbsent('Content-Length', () => [])
        .add(contentLength.toString());
  });

  when(mockRequestHeaders.contentType).thenAnswer((invocation) {
    return contentType;
  });
  when(mockRequestHeaders.contentType = any).thenAnswer((invocation) {
    final contentTypeArg = invocation.positionalArguments[0] as ContentType;
    contentType = contentTypeArg;
    requestHeaders.putIfAbsent(HttpHeaders.contentTypeHeader,
        () => [contentType?.primaryType ?? "", contentType?.subType ?? ""]);
  });

  when(mockRequestHeaders[any]).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    return requestHeaders.putIfAbsent(name, () => []);
  });

  when(mockRequestHeaders.forEach(any)).thenAnswer((invocation) {
    Function(String, List<String>)? callback =
        invocation.positionalArguments[0];
    requestHeaders.forEach((key, values) {
      callback!(key, values);
    });
  });

  when(mockRequestHeaders.add(any, any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final value = invocation.positionalArguments[1].toString();
    requestHeaders.putIfAbsent(name, () => []).add(value);
  });

  when(mockRequestHeaders.set(any, any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final value = invocation.positionalArguments[1].toString();
    requestHeaders[name] = [value];
  });

  when(mockRequestHeaders.value(any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final values = requestHeaders[name];
    if (values == null) return null;
    return values.join(', ');
  });

  when(mockRequestHeaders[any]).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final val = requestHeaders.putIfAbsent(name, () => []);
    return val;
  });

  return mockRequestHeaders;
}
