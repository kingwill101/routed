import 'dart:io';

import 'package:mockito/mockito.dart';
import 'package:server_testing/src/mock.mocks.dart';

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
  List<Cookie> cookies = [];

  // Parse existing cookies from headers
  if (requestHeaders.containsKey(HttpHeaders.cookieHeader)) {
    for (final cookieHeader in requestHeaders[HttpHeaders.cookieHeader]!) {
      for (final singleCookie in cookieHeader.split(';')) {
        final parts = singleCookie.trim().split('=');
        if (parts.length == 2) {
          cookies.add(Cookie(parts[0].trim(), parts[1].trim()));
        }
      }
    }
  }

  // Handle cookie header value
  when(mockRequestHeaders.value(HttpHeaders.cookieHeader)).thenAnswer((_) {
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  });

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
    requestHeaders.putIfAbsent(
        HttpHeaders.contentTypeHeader, () => [contentType?.value ?? '']);
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

  // Handle Set-Cookie headers properly
  when(mockRequestHeaders.add(any, any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final value = invocation.positionalArguments[1].toString();

    if (name.toLowerCase() == HttpHeaders.setCookieHeader.toLowerCase()) {
      // For Set-Cookie, maintain list of values
      requestHeaders.putIfAbsent(name, () => []).add(value);
    } else {
      // For other headers, replace
      requestHeaders[name] = [value];
    }
  });

  // Add cookie removal capability
  when(mockRequestHeaders.removeAll(any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    requestHeaders.remove(name);
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
