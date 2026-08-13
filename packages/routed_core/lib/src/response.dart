import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_core/src/http/adapter_http.dart';
import 'package:routed_core/src/http/transport.dart';

typedef ResponseBodyFilter = List<int> Function(List<int> body);

/// A class that represents an HTTP response.
///
/// Dual-mode: native `dart:io` [HttpResponse] **or** portable [ResponseAdapter].
class Response {
  /// Native IO response when constructed via [Response.new].
  final HttpResponse? _httpResponse;

  /// Portable adapter when constructed via [Response.fromAdapter].
  final ResponseAdapter? _adapter;

  /// Map-backed headers for the portable path (also mirrored into [_headers]).
  final AdapterHttpHeaders? _portableHeaders;

  /// Cookies for the portable path (written as Set-Cookie on flush).
  final List<Cookie> _portableCookies = <Cookie>[];

  final _buffer = BytesBuilder();
  final _headers = <String, List<String>>{};
  bool _headersWritten = false;
  bool _bodyStarted = false;
  bool _isClosed = false;
  int _portableStatusCode = HttpStatus.ok;
  ResponseBodyFilter? _bodyFilter;
  final Completer<void> _portableDone = Completer<void>();

  /// Constructs a Response with a native [HttpResponse].
  Response(HttpResponse httpResponse)
    : _httpResponse = httpResponse,
      _adapter = null,
      _portableHeaders = null;

  /// Constructs a Response that writes through a portable [ResponseAdapter].
  Response.fromAdapter(ResponseAdapter adapter)
    : _httpResponse = null,
      _adapter = adapter,
      _portableHeaders = AdapterHttpHeaders();

  /// Whether this response is backed by a real `dart:io` [HttpResponse].
  bool get hasNativeHttpResponse => _httpResponse != null;

  /// Whether this response is portable-adapter backed.
  bool get isPortable => _adapter != null;

  /// Returns whether the response is closed.
  bool get isClosed => _isClosed;

  /// Controls whether output is buffered before streaming (native only).
  bool get bufferOutput => _httpResponse?.bufferOutput ?? true;

  set bufferOutput(bool value) {
    _httpResponse?.bufferOutput = value;
  }

  /// A future that completes when the underlying HTTP response finishes.
  Future<void> get done => _httpResponse?.done ?? _portableDone.future;

  /// Gets the content length of the HTTP response.
  int? get contentLength {
    final native = _httpResponse;
    if (native != null) return native.contentLength;
    final len = _portableHeaders!.contentLength;
    return len < 0 ? null : len;
  }

  /// Gets the persistent connection state of the HTTP response.
  bool get persistentConnection => _httpResponse?.persistentConnection ?? true;

  /// Gets the reason phrase of the HTTP response.
  String? get reasonPhrase => _httpResponse?.reasonPhrase;

  /// Gets the transfer encoding of the HTTP response.
  bool get hasTransferEncoding {
    final native = _httpResponse;
    if (native != null) {
      return native.headers[HttpHeaders.transferEncodingHeader] != null;
    }
    return _portableHeaders![HttpHeaders.transferEncodingHeader] != null;
  }

  /// Gets the content type of the HTTP response.
  String? get contentType {
    final native = _httpResponse;
    if (native != null) return native.headers.contentType?.value;
    return _portableHeaders!.contentType?.value;
  }

  /// Gets the cookies of the HTTP response.
  List<Cookie> get cookies {
    final native = _httpResponse;
    if (native != null) return native.cookies;
    return List<Cookie>.unmodifiable(_portableCookies);
  }

  /// Gets the local port of the HTTP connection (native only).
  int? get localPort => _httpResponse?.connectionInfo?.localPort;

  /// Gets the remote address of the HTTP connection.
  String? get remoteAddress =>
      _httpResponse?.connectionInfo?.remoteAddress.address;

  /// Gets the remote port of the HTTP connection (native only).
  int? get remotePort => _httpResponse?.connectionInfo?.remotePort;

  void _writeStatus(int statusCode) {
    final native = _httpResponse;
    if (native != null) {
      native.statusCode = statusCode;
    } else {
      _portableStatusCode = statusCode;
      _adapter!.statusCode = statusCode;
    }
  }

  void _writeBytesToSink(List<int> data) {
    final native = _httpResponse;
    if (native != null) {
      native.add(data);
    } else {
      _adapter!.write(data);
    }
  }

  void _writeObjectToSink(Object? data) {
    final native = _httpResponse;
    if (native != null) {
      native.write(data);
    } else {
      _adapter!.write(utf8.encode(data?.toString() ?? ''));
    }
  }

  /// Writes [data] to the response.
  void write(dynamic data) {
    _ensureNotClosed();
    if (!_bodyStarted) {
      _buffer.add(utf8.encode(data.toString()));
    } else {
      _writeObjectToSink(data);
    }
  }

  /// Writes a list of bytes [data] to the response.
  void writeBytes(List<int> data) {
    _ensureNotClosed();
    if (!_bodyStarted) {
      _buffer.add(data);
    } else {
      _writeBytesToSink(data);
    }
  }

  /// Writes the headers to the HTTP response.
  void writeHeaderNow() {
    _ensureNotClosed();
    if (_headersWritten) return;

    final native = _httpResponse;
    if (native != null) {
      _headers.forEach((name, values) {
        if (name.toLowerCase() == HttpHeaders.setCookieHeader.toLowerCase()) {
          for (final value in values) {
            native.headers.add(name, value);
          }
        } else {
          native.headers.set(name, values.join(', '));
        }
      });

      for (final cookie in native.cookies) {
        native.headers.add(HttpHeaders.setCookieHeader, cookie.toString());
      }
    } else {
      final adapter = _adapter!;
      adapter.statusCode = _portableStatusCode;
      _headers.forEach((name, values) {
        if (name.toLowerCase() == HttpHeaders.setCookieHeader.toLowerCase()) {
          for (final value in values) {
            adapter.addHeader(name, value);
          }
        } else {
          adapter.setHeader(name, values.join(', '));
        }
      });
      for (final cookie in _portableCookies) {
        adapter.addHeader(HttpHeaders.setCookieHeader, cookie.toString());
      }
      // Also flush AdapterHttpHeaders mutations (content-type etc.).
      _portableHeaders!.forEach((name, values) {
        if (name.toLowerCase() == HttpHeaders.setCookieHeader.toLowerCase()) {
          return;
        }
        if (!_headers.containsKey(name) &&
            !_headers.keys.any((k) => k.toLowerCase() == name.toLowerCase())) {
          adapter.setHeader(name, values.join(', '));
        }
      });
    }

    _headersWritten = true;
  }

  /// Writes the buffered data to the HTTP response and starts the body.
  void writeNow() {
    _ensureNotClosed();
    writeHeaderNow();
    Uint8List bytes = _buffer.takeBytes();
    if (_bodyFilter != null) {
      try {
        final transformed = _bodyFilter!(bytes);
        if (transformed is Uint8List) {
          bytes = transformed;
        } else {
          bytes = Uint8List.fromList(transformed);
        }
      } finally {
        _bodyFilter = null;
      }
    }

    final native = _httpResponse;
    if (native != null) {
      if (native.contentLength < 0) {
        if (native.headers.chunkedTransferEncoding) {
          native.headers.chunkedTransferEncoding = false;
        }
        native.contentLength = bytes.length;
      }
      // ignore: unnecessary_statements
      native.headers[HttpHeaders.transferEncodingHeader];
      native.add(bytes);
    } else {
      if (bytes.isNotEmpty) {
        _adapter!.write(bytes);
      }
    }
    _bodyStarted = true;
  }

  /// Closes the response.
  Future<void> close() async {
    if (_isClosed) return;
    if (!_bodyStarted) {
      writeNow();
    }
    _isClosed = true;
    try {
      final native = _httpResponse;
      if (native != null) {
        await native.close();
      } else {
        await _adapter!.close();
        if (!_portableDone.isCompleted) _portableDone.complete();
      }
    } catch (_) {
      // Ignore: underlying already closed
    }
  }

  void _ensureNotClosed() {
    if (_isClosed) {
      throw StateError('Cannot write to a closed response.');
    }
  }

  /// Sends a string [content] as the response body with an optional [statusCode].
  Future<void> string(String content, {int statusCode = HttpStatus.ok}) async {
    _ensureNotClosed();
    _writeStatus(statusCode);
    final bytes = utf8.encode(content);
    final native = _httpResponse;
    if (native != null) {
      native.contentLength = bytes.length;
    }
    write(content);
    await close();
  }

  /// Sends a JSON [data] as the response body with an optional [statusCode].
  Future<void> json(Object? data, {int statusCode = HttpStatus.ok}) async {
    _ensureNotClosed();
    _writeStatus(statusCode);
    _headers['Content-Type'] = ['application/json; charset=utf-8'];
    final encoded = jsonEncode(data);
    final bytes = utf8.encode(encoded);
    final native = _httpResponse;
    if (native != null) {
      native.contentLength = bytes.length;
    }
    write(encoded);
    await close();
  }

  /// Sends an error [message] as the response body with an optional [statusCode].
  void error(
    String message, {
    int statusCode = HttpStatus.internalServerError,
  }) {
    if (_isClosed) return;
    _writeStatus(statusCode);
    write(message);
    close();
  }

  /// Adds a stream of bytes [stream] to the response.
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureNotClosed();
    writeHeaderNow();
    _bodyStarted = true;
    final native = _httpResponse;
    if (native != null) {
      await native.addStream(stream);
    } else {
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) _adapter!.write(chunk);
      }
    }
  }

  /// Flushes any buffered data to the client immediately.
  Future<void> flush() async {
    _ensureNotClosed();
    if (!_bodyStarted) {
      writeNow();
    }
    final native = _httpResponse;
    if (native != null) {
      await native.flush();
    } else {
      await _adapter!.flush();
    }
  }

  /// Detaches the underlying socket (native path only).
  Future<Socket> detachSocket({bool writeHeaders = true}) async {
    _ensureNotClosed();
    final native = _httpResponse;
    if (native == null) {
      throw UnsupportedError(
        'detachSocket is not supported on portable responses',
      );
    }
    _isClosed = true;
    return await native.detachSocket(writeHeaders: writeHeaders);
  }

  /// Sends a file [file] as a downloadable attachment (native path preferred).
  HttpResponse download(
    File file, {
    String? name,
    Map<String, String>? headers,
  }) {
    _ensureNotClosed();
    final native = _httpResponse;
    if (native == null) {
      throw UnsupportedError(
        'download() requires a native dart:io HttpResponse; '
        'use writeBytes/addStream on portable hosts',
      );
    }
    native.statusCode = HttpStatus.ok;
    _headers['Content-Type'] = ['application/octet-stream'];
    _headers['Content-Disposition'] = [
      'attachment; filename="${name ?? file.uri.pathSegments.last}"',
    ];

    headers?.forEach((key, value) {
      _headers[key] = [value];
    });

    writeHeaderNow();
    _bodyStarted = true;
    file.openRead().pipe(native);
    return native;
  }

  /// Redirects the response to a [location].
  ///
  /// Returns the native [HttpResponse] when available; otherwise null after
  /// scheduling close on the portable path.
  HttpResponse? redirect(
    String location, {
    int status = HttpStatus.found,
    Map<String, String>? headers,
  }) {
    _ensureNotClosed();
    _writeStatus(status);
    _headers['Location'] = [location];

    headers?.forEach((key, value) {
      _headers[key] = [value];
    });

    close();
    return _httpResponse;
  }

  /// Sets a cookie with the given [name] and [value], and optional parameters.
  void setCookie(
    String name,
    dynamic value, {
    int? maxAge,
    String path = '/',
    String domain = '',
    bool secure = false,
    bool httpOnly = false,
    SameSite? sameSite,
  }) {
    _ensureNotClosed();
    final String stringValue = value is String ? value : value.toString();
    final cookie = Cookie(name, stringValue)
      ..maxAge = maxAge
      ..path = path
      ..secure = secure
      ..httpOnly = httpOnly
      ..sameSite = sameSite;
    if (domain.isNotEmpty) {
      cookie.domain = domain;
    }

    final native = _httpResponse;
    if (native != null) {
      native.cookies.removeWhere((c) => c.name == name);
      native.cookies.add(cookie);
    } else {
      _portableCookies.removeWhere((c) => c.name == name);
      _portableCookies.add(cookie);
    }
  }

  /// Returns the headers of the HTTP response.
  HttpHeaders get headers => _httpResponse?.headers ?? _portableHeaders!;

  /// Gets the status code of the HTTP response.
  int get statusCode => _httpResponse?.statusCode ?? _portableStatusCode;

  /// Sets the status code of the HTTP response.
  set statusCode(int value) {
    if (_isClosed || _headersWritten || _bodyStarted) {
      return;
    }
    _writeStatus(value);
  }

  /// Adds a header with the given [name] and [value] to the response.
  void addHeader(String name, String value) {
    _ensureNotClosed();
    if (name.toLowerCase() == HttpHeaders.setCookieHeader) {
      _headers.putIfAbsent(name, () => []).add(value);
    } else {
      final existing = _headers[name];
      if (existing != null) {
        _headers[name] = [...existing, value];
      } else {
        _headers[name] = [value];
      }
    }
  }

  /// Adds a header with the given [name] and [value] to the response.
  void setHeader(String name, String value) {
    _ensureNotClosed();
    final native = _httpResponse;
    if (native != null) {
      native.headers.set(name, value);
    } else {
      _portableHeaders!.set(name, value);
      _headers[name] = [value];
    }
  }

  /// Removes a header with the given [name] from the response.
  void removeHeader(String name, {Object? value}) {
    _ensureNotClosed();
    final native = _httpResponse;
    if (native != null) {
      if (value != null) {
        native.headers.remove(name, value);
      } else {
        native.headers.removeAll(name);
      }
    } else {
      if (value != null) {
        _portableHeaders!.remove(name, value);
      } else {
        _portableHeaders!.removeAll(name);
      }
    }
    _headers.remove(name);
  }

  /// Registers a one-time filter that can transform the buffered body before it
  /// is written to the underlying sink.
  void setBodyFilter(ResponseBodyFilter? filter) {
    if (_bodyStarted || _isClosed) {
      return;
    }
    _bodyFilter = filter;
  }
}

/// A class that represents a streamed HTTP response.
class StreamedResponse {
  final Stream<List<int>> stream;
  final int statusCode;
  final Map<String, String>? headers;

  /// Constructs a StreamedResponse with the given [stream], [statusCode], and optional [headers].
  StreamedResponse(this.stream, this.statusCode, {this.headers});
}
