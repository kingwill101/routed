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
/// ## Example
///
///
/// final headers = &ltString, List&ltString&gt&gt{};
/// final mockHeaders = setupHeaders(headers);
///
/// // Set content type and observe it reflected in the map
/// mockHeaders.contentType = ContentType.json;
/// print(headers['content-type']); // ['application/json; charset=utf-8']
///
/// // Add a custom header
/// mockHeaders.add('X-Custom-Header', 'Value');
/// print(headers['X-Custom-Header']); // ['Value']
///
///
/// This is primarily used for testing HTTP request/response handling where
/// header manipulation is needed without real HTTP connections.
MockHttpHeaders setupHeaders(Map<String, List<String>> requestHeaders) {
  final mockRequestHeaders = MockHttpHeaders();
  ContentType? contentType;
  List<Cookie> cookies = [];

  String normalizeHeaderName(String name) => name.toLowerCase();

  // Parse existing cookies from headers
  final cookieHeaderName = normalizeHeaderName(HttpHeaders.cookieHeader);
  if (requestHeaders.keys.map(normalizeHeaderName).contains(cookieHeaderName)) {
    final cookieValues = requestHeaders.entries
        .firstWhere((e) => normalizeHeaderName(e.key) == cookieHeaderName)
        .value;
    for (final cookieHeader in cookieValues) {
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

  // Initialize content type from existing headers if present
  final contentTypeHeaderName =
      normalizeHeaderName(HttpHeaders.contentTypeHeader);
  for (final entry in requestHeaders.entries) {
    if (normalizeHeaderName(entry.key) == contentTypeHeaderName) {
      contentType = ContentType.parse(entry.value.join(", "));
      break;
    }
  }

  // Handle content length setter
  when(mockRequestHeaders.contentLength = any).thenAnswer((invocation) {
    final contentLength = invocation.positionalArguments[0] as int;
    requestHeaders
        .putIfAbsent('content-length', () => [])
        .add(contentLength.toString());
  });

  // Handle content type getter/setter
  when(mockRequestHeaders.contentType).thenAnswer((invocation) {
    return contentType;
  });

  when(mockRequestHeaders.contentType = any).thenAnswer((invocation) {
    final contentTypeArg = invocation.positionalArguments[0] as ContentType;
    contentType = contentTypeArg;
    requestHeaders[HttpHeaders.contentTypeHeader] = [contentType?.value ?? ''];
  });

  // Handle header access by name
  when(mockRequestHeaders[any]).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final normalizedName = normalizeHeaderName(name);
    final existingKey = requestHeaders.keys.firstWhere(
        (k) => normalizeHeaderName(k) == normalizedName,
        orElse: () => name);
    return requestHeaders.putIfAbsent(existingKey, () => []);
  });


  // Handle iteration over headers
  when(mockRequestHeaders.forEach(any)).thenAnswer((invocation) {
    final callback =
        invocation.positionalArguments[0] as void Function(String, List<String>)?;
    requestHeaders.forEach((key, values) {
      callback!(key, values);
    });
  });

  // Handle Set-Cookie headers properly - they accumulate multiple values
  when(mockRequestHeaders.add(any, any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final value = invocation.positionalArguments[1].toString();
    final normalizedName = normalizeHeaderName(name);

    if (normalizedName == normalizeHeaderName(HttpHeaders.setCookieHeader)) {
      // For Set-Cookie, maintain list of values
      final existingKey = requestHeaders.keys.firstWhere(
          (k) => normalizeHeaderName(k) == normalizedName,
          orElse: () => name);
      requestHeaders.putIfAbsent(existingKey, () => []).add(value);
    } else {
      // For other headers, replace
      final existingKey = requestHeaders.keys.firstWhere(
          (k) => normalizeHeaderName(k) == normalizedName,
          orElse: () => name);
      requestHeaders[existingKey] = [value];
    }
  });

  // Add cookie removal capability
  when(mockRequestHeaders.removeAll(any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final normalizedName = normalizeHeaderName(name);
    requestHeaders
        .removeWhere((k, _) => normalizeHeaderName(k) == normalizedName);
  });

  // Handle setting header values
  when(mockRequestHeaders.set(any, any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final value = invocation.positionalArguments[1].toString();
    final normalizedName = normalizeHeaderName(name);
    final existingKey = requestHeaders.keys.firstWhere(
        (k) => normalizeHeaderName(k) == normalizedName,
        orElse: () => name);
    requestHeaders[existingKey] = [value];
  });

  // Handle getting singular header value
  when(mockRequestHeaders.value(any)).thenAnswer((invocation) {
    final name = invocation.positionalArguments[0].toString();
    final normalizedName = normalizeHeaderName(name);
    final key = requestHeaders.keys.firstWhere(
        (k) => normalizeHeaderName(k) == normalizedName,
        orElse: () => '');
    final values = requestHeaders[key];
    if (values == null) return null;
    return values.join(', ');
  });

  return mockRequestHeaders;
}
