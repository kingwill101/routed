import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A class that represents an HTTP response.
class Response {
  final HttpResponse _httpResponse;
  final _buffer = BytesBuilder();
  final _headers = <String, List<String>>{};
  bool _headersWritten = false;
  bool _bodyStarted = false;
  bool _isClosed = false;

  /// Constructs a Response object with the given [HttpResponse].
  Response(this._httpResponse);

  /// Returns whether the response is closed.
  bool get isClosed => _isClosed;

  /// Gets the content length of the HTTP response.
  int? get contentLength => _httpResponse.contentLength;

  /// Gets the persistent connection state of the HTTP response.
  bool get persistentConnection => _httpResponse.persistentConnection;

  /// Gets the reason phrase of the HTTP response.
  String? get reasonPhrase => _httpResponse.reasonPhrase;

  /// Gets the transfer encoding of the HTTP response.
  bool get hasTransferEncoding =>
      _httpResponse.headers[HttpHeaders.transferEncodingHeader] != null;

  /// Gets the content type of the HTTP response.
  String? get contentType => _httpResponse.headers.contentType?.value;

  /// Gets the cookies of the HTTP response.
  List<Cookie> get cookies => _httpResponse.cookies;

  /// Gets the local port of the HTTP connection.
  int? get localPort => _httpResponse.connectionInfo?.localPort;

  /// Gets the remote address of the HTTP connection.
  String? get remoteAddress =>
      _httpResponse.connectionInfo?.remoteAddress.address;

  /// Gets the remote port of the HTTP connection.
  int? get remotePort => _httpResponse.connectionInfo?.remotePort;

  /// Writes [data] to the response.
  /// If the body has not started, the data is added to the buffer.
  /// Otherwise, it is written directly to the HTTP response.
  void write(dynamic data) {
    _ensureNotClosed();
    if (!_bodyStarted) {
      _buffer.add(utf8.encode(data.toString()));
    } else {
      _httpResponse.write(data);
    }
  }

  /// Writes a list of bytes [data] to the response.
  /// If the body has not started, the data is added to the buffer.
  /// Otherwise, it is added directly to the HTTP response.
  void writeBytes(List<int> data) {
    _ensureNotClosed();
    if (!_bodyStarted) {
      _buffer.add(data);
    } else {
      _httpResponse.add(data);
    }
  }

  /// Writes the headers to the HTTP response.
  void writeHeaderNow() {
    _ensureNotClosed();
    if (!_headersWritten) {
      _headers.forEach((name, values) {
        _httpResponse.headers.set(name, values.join(', '));
      });
      _headersWritten = true;
    }
  }

  /// Writes the buffered data to the HTTP response and starts the body.
  void writeNow() {
    _ensureNotClosed();
    writeHeaderNow();
    _httpResponse.add(_buffer.takeBytes());
    _bodyStarted = true;
  }

  /// Closes the response.
  /// If the body has not started, it writes the buffered data first.
  void close() {
    if (_isClosed) return;
    if (!_bodyStarted) {
      writeNow();
    }
    _isClosed = true;
    _httpResponse.close();
  }

  void _ensureNotClosed() {
    if (_isClosed) {
      throw StateError('Cannot write to a closed response.');
    }
  }

  /// Sends a string [content] as the response body with an optional [statusCode].
  Future<void> string(String content, {int statusCode = HttpStatus.ok}) async {
    _ensureNotClosed();
    _httpResponse.statusCode = statusCode;
    write(content);
    close();
  }

  /// Sends a JSON [data] as the response body with an optional [statusCode].
  Future<void> json(Map<String, dynamic> data,
      {int statusCode = HttpStatus.ok}) async {
    _ensureNotClosed();
    _httpResponse.statusCode = statusCode;
    _headers['Content-Type'] = ['application/json; charset=utf-8'];
    write(jsonEncode(data));
    close();
  }

  /// Sends an error [message] as the response body with an optional [statusCode].
  void error(String message,
      {int statusCode = HttpStatus.internalServerError}) {
    if (_isClosed) return;
    _httpResponse.statusCode = statusCode;
    write(message);
    close();
  }

  /// Adds a stream of bytes [stream] to the response.
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureNotClosed();
    writeHeaderNow();
    _bodyStarted = true;
    await _httpResponse.addStream(stream);
  }

  /// Sends a file [file] as a downloadable attachment with an optional [name] and [headers].
  HttpResponse download(File file,
      {String? name, Map<String, String>? headers}) {
    _ensureNotClosed();
    _httpResponse.statusCode = HttpStatus.ok;
    _headers['Content-Type'] = ['application/octet-stream'];
    _headers['Content-Disposition'] = [
      'attachment; filename="${name ?? file.uri.pathSegments.last}"'
    ];

    headers?.forEach((key, value) {
      _headers[key] = [value];
    });

    writeHeaderNow();
    _bodyStarted = true;
    file.openRead().pipe(_httpResponse);
    return _httpResponse;
  }

  /// Redirects the response to a [location] with an optional [status] and [headers].
  HttpResponse redirect(String location,
      {int status = HttpStatus.found, Map<String, String>? headers}) {
    _ensureNotClosed();
    _httpResponse.statusCode = status;
    _headers['Location'] = [location];

    headers?.forEach((key, value) {
      _headers[key] = [value];
    });

    close();
    return _httpResponse;
  }

  /// Sets a cookie with the given [name] and [value], and optional parameters.
  void setCookie(String name, dynamic value,
      {int? maxAge,
      String path = '/',
      String domain = '',
      bool secure = false,
      bool httpOnly = false,
      SameSite? sameSite}) {
    _ensureNotClosed();
    final String stringValue = value is String ? value : value.toString();
    final cookie = Cookie(name, stringValue)
      ..maxAge = maxAge
      ..path = path
      ..domain = domain
      ..secure = secure
      ..httpOnly = httpOnly
      ..sameSite = sameSite;

    // Remove existing cookies with same name
    _httpResponse.cookies.removeWhere((c) => c.name == name);
    _httpResponse.cookies.add(cookie);

    // Update headers collection
    final existing = _headers[HttpHeaders.setCookieHeader] ?? [];
    _headers[HttpHeaders.setCookieHeader] = [
      ...existing.where((h) => !h.startsWith('$name=')),
      cookie.toString()
    ];
  }

  /// Returns the headers of the HTTP response.
  HttpHeaders get headers => _httpResponse.headers;

  /// Gets the status code of the HTTP response.
  int get statusCode => _httpResponse.statusCode;

  /// Sets the status code of the HTTP response.
  set statusCode(int value) => _httpResponse.statusCode = value;

  /// Returns the underlying [HttpResponse] object.
  HttpResponse get httpResponse => _httpResponse;

  /// Adds a header with the given [name] and [value] to the response.
  void addHeader(String name, String value) {
    _ensureNotClosed();
    if (name.toLowerCase() == HttpHeaders.setCookieHeader) {
      // Special case: Set-Cookie headers are always separate
      _headers.putIfAbsent(name, () => []).add(value);
    } else {
      // Standard case: Combine with comma-separation
      final existing = _headers[name];
      if (existing != null) {
        _headers[name] = [...existing, value]; // Preserve order
      } else {
        _headers[name] = [value];
      }
    }
  }

  /// Adds a header with the given [name] and [value] to the response.
  void setHeader(String name, String value) {
    _ensureNotClosed();
    _httpResponse.headers.set(name, value);
  }

  /// Removes a header with the given [name] from the response.
  void removeHeader(String name, {Object? value}) {
    _ensureNotClosed();
    if (value != null) {
      _httpResponse.headers.remove(name, value);
    } else {
      _httpResponse.headers.removeAll(name);
    }
    _headers.remove(name);
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
