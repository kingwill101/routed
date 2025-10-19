import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mockito/mockito.dart';
import 'package:server_testing/src/mock.mocks.dart';
import 'package:server_testing/src/mock/headers.dart';

/// A custom list that syncs cookie changes to Set-Cookie headers.
/// This replicates the behavior of a real HttpResponse where cookies
/// are automatically synchronized to headers.
class SyncedCookieList extends ListBase<Cookie> {
  final List<Cookie> _inner;
  final Map<String, List<String>> _headers;

  SyncedCookieList(this._inner, this._headers);

  @override
  int get length => _inner.length;

  @override
  set length(int newLength) {
    _inner.length = newLength;
    _syncToHeaders();
  }

  @override
  Cookie operator [](int index) => _inner[index];

  @override
  void operator []=(int index, Cookie value) {
    _inner[index] = value;
    _syncToHeaders();
  }

  @override
  void add(Cookie element) {
    _inner.add(element);
    _syncToHeaders();
  }

  @override
  void addAll(Iterable<Cookie> iterable) {
    _inner.addAll(iterable);
    _syncToHeaders();
  }

  @override
  bool remove(Object? element) {
    final result = _inner.remove(element);
    if (result) _syncToHeaders();
    return result;
  }

  @override
  void removeWhere(bool Function(Cookie) test) {
    _inner.removeWhere(test);
    _syncToHeaders();
  }

  @override
  void clear() {
    _inner.clear();
    _syncToHeaders();
  }

  /// Syncs the current cookie list to Set-Cookie headers
  void _syncToHeaders() {
    // Remove all existing Set-Cookie headers
    _headers.removeWhere(
      (key, _) =>
          key.toLowerCase() == HttpHeaders.setCookieHeader.toLowerCase(),
    );

    // Add Set-Cookie headers for each cookie
    if (_inner.isNotEmpty) {
      _headers[HttpHeaders.setCookieHeader] = _inner.map((cookie) {
        final buffer = StringBuffer();
        buffer.write('${cookie.name}=${cookie.value}');

        if (cookie.path != null) {
          buffer.write('; Path=${cookie.path}');
        }
        if (cookie.domain != null && cookie.domain!.isNotEmpty) {
          buffer.write('; Domain=${cookie.domain}');
        }
        if (cookie.maxAge != null) {
          buffer.write('; Max-Age=${cookie.maxAge}');
        }
        if (cookie.expires != null) {
          buffer.write('; Expires=${HttpDate.format(cookie.expires!)}');
        }
        if (cookie.secure) {
          buffer.write('; Secure');
        }
        if (cookie.httpOnly) {
          buffer.write('; HttpOnly');
        }
        if (cookie.sameSite != null) {
          final sameSiteValue = cookie.sameSite == SameSite.lax
              ? 'Lax'
              : cookie.sameSite == SameSite.strict
              ? 'Strict'
              : 'None';
          buffer.write('; SameSite=$sameSiteValue');
        }

        return buffer.toString();
      }).toList();
    }
  }
}

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
MockHttpResponse setupResponse({
  Map<String, List<String>>? headers,
  List<Cookie>? cookies,
  BytesBuilder? body,
}) {
  final mockResponse = MockHttpResponse();
  headers ??= {};
  body ??= BytesBuilder();

  // Track real HttpResponse-like state
  var headersSent = false;
  var bodyStarted = false;
  var closed = false;

  void ensureHeadersNotSent() {
    if (headersSent || bodyStarted || closed) {
      throw StateError('Header already sent');
    }
  }

  void ensureNotClosed() {
    if (closed) {
      throw StateError('Response is closed');
    }
  }

  // Setup cookies
  if (cookies != null && cookies.isNotEmpty) {
    headers[HttpHeaders.cookieHeader] = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .toList();
  }

  headers.remove(HttpHeaders.cookieHeader);

  // Create a synced cookie list that automatically updates headers
  final syncedCookieList = SyncedCookieList([...?cookies], headers);
  when(mockResponse.cookies).thenAnswer((_) => syncedCookieList);

  int statusCode = HttpStatus.ok;
  final mockResponseHeaders = setupHeaders(headers);
  when(mockResponse.statusCode).thenAnswer((_) => statusCode);
  when(mockResponse.statusCode = any).thenAnswer((invocation) {
    ensureHeadersNotSent();
    statusCode = invocation.positionalArguments.first as int;
  });

  // Mock headers getter and setup headers
  when(mockResponse.headers).thenAnswer((i) => mockResponseHeaders);

  // write/add/addStream mark body started and implicitly send headers
  when(mockResponse.write(any)).thenAnswer((invocation) {
    ensureNotClosed();
    headersSent = true;
    bodyStarted = true;
    final data = invocation.positionalArguments[0].toString();
    body?.add(utf8.encode(data));
  });

  when(mockResponse.addStream(any)).thenAnswer((invocation) async {
    ensureNotClosed();
    headersSent = true;
    bodyStarted = true;
    final stream = invocation.positionalArguments[0] as Stream<List<int>>;
    await for (final chunk in stream) {
      body?.add(chunk);
    }
  });

  when(mockResponse.add(any)).thenAnswer((invocation) {
    ensureNotClosed();
    headersSent = true;
    bodyStarted = true;
    final data = invocation.positionalArguments[0] as List<int>;
    body?.add(data);
  });

  // Mock close method to finalize the response
  when(mockResponse.close()).thenAnswer((_) async {
    ensureNotClosed();
    headersSent = true;
    closed = true;
  });

  return mockResponse;
}
