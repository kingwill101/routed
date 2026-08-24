import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_core/src/http/transport.dart';
import 'package:routed_core/src/request.dart' show Request;

/// Builds a synthetic [HttpRequest]/[HttpResponse] pair from portable adapters
/// so the existing engine pipeline can handle non-`dart:io` hosts.
///
/// Host packages (`routed_node`, Workers, …) implement [RequestAdapter] /
/// [ResponseAdapter]; this bridge is the transitional shim until the pipeline
/// is fully adapter-native.
final class AdapterHttpBridge {
  AdapterHttpBridge._();

  /// Creates an `HttpRequest` whose body and headers come from
  /// `HttpConnection.request` and whose response writes through
  /// `HttpConnection.response`.
  ///
  /// The synthetic response is closed by the engine pipeline after the request
  /// finishes (same lifecycle as a real `dart:io` response).
  static HttpRequest toHttpRequest(HttpConnection connection) {
    // ignore: close_sinks
    final response = AdapterHttpResponse(connection.response);
    return AdapterHttpRequest(connection.request, response);
  }
}

/// Map-backed [HttpHeaders] suitable for adapter hosts.
final class AdapterHttpHeaders implements HttpHeaders {
  /// Creates headers populated with [initial] values.
  AdapterHttpHeaders([Map<String, List<String>>? initial]) {
    if (initial != null) {
      initial.forEach((name, values) {
        for (final v in values) {
          add(name, v, preserveHeaderCase: true);
        }
      });
    }
  }

  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};
  final Set<String> _noFolding = <String>{};
  bool _suppressFieldUpdates = false;

  DateTime? _date;
  DateTime? _expires;
  DateTime? _ifModifiedSince;
  String? _host;
  int? _port;
  ContentType? _contentType;
  int _contentLength = -1;
  bool _persistentConnection = true;
  bool _chunkedTransferEncoding = false;

  @override
  DateTime? get date => _date;

  @override
  set date(DateTime? value) {
    _date = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.dateHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
    );
  }

  @override
  DateTime? get expires => _expires;

  @override
  set expires(DateTime? value) {
    _expires = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.expiresHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
    );
  }

  @override
  DateTime? get ifModifiedSince => _ifModifiedSince;

  @override
  set ifModifiedSince(DateTime? value) {
    _ifModifiedSince = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.ifModifiedSinceHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
    );
  }

  @override
  String? get host => _host;

  @override
  set host(String? value) {
    _host = value;
    _updateHostHeader();
  }

  @override
  int? get port => _port;

  @override
  set port(int? value) {
    _port = value;
    _updateHostHeader();
  }

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.contentTypeHeader,
        value == null ? null : <String>[value.toString()],
      ),
    );
  }

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
    _runWithoutUpdate(() {
      if (value < 0) {
        _setValues(HttpHeaders.contentLengthHeader, null);
      } else {
        _setValues(HttpHeaders.contentLengthHeader, <String>[value.toString()]);
      }
    });
  }

  @override
  bool get persistentConnection => _persistentConnection;

  @override
  set persistentConnection(bool value) {
    _persistentConnection = value;
    _runWithoutUpdate(() {
      if (value) {
        remove(HttpHeaders.connectionHeader, 'close');
      } else {
        _setValues(HttpHeaders.connectionHeader, <String>['close']);
      }
    });
  }

  @override
  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  @override
  set chunkedTransferEncoding(bool value) {
    _chunkedTransferEncoding = value;
    _runWithoutUpdate(() {
      if (value) {
        _setValues(HttpHeaders.transferEncodingHeader, <String>['chunked']);
      } else {
        remove(HttpHeaders.transferEncodingHeader, 'chunked');
      }
    });
  }

  @override
  List<String>? operator [](String name) {
    final values = _headers[_normalize(name)];
    return values == null ? null : List<String>.from(values);
  }

  @override
  String? value(String name) {
    final values = _headers[_normalize(name)];
    if (values == null || values.isEmpty) return null;
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    final values = _headers.putIfAbsent(normalized, () => <String>[]);
    if (value is Iterable && value is! String) {
      for (final v in value) {
        values.add(_valueToString(v));
      }
    } else {
      values.add(_valueToString(value));
    }
    if (preserveHeaderCase) {
      _originalNames[normalized] = name;
    } else {
      _originalNames.putIfAbsent(normalized, () => name);
    }
    _updateComputedFields(normalized);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    add(name, value, preserveHeaderCase: preserveHeaderCase);
  }

  @override
  void remove(String name, Object value) {
    final normalized = _normalize(name);
    final values = _headers[normalized];
    if (values == null) return;
    final stringValue = _valueToString(value);
    values.removeWhere((element) => element == stringValue);
    if (values.isEmpty) {
      _headers.remove(normalized);
      _originalNames.remove(normalized);
    }
    _updateComputedFields(normalized);
  }

  @override
  void removeAll(String name) {
    final normalized = _normalize(name);
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    _updateComputedFields(normalized);
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach((key, values) {
      action(_originalNames[key] ?? key, List<String>.from(values));
    });
  }

  @override
  void noFolding(String name) {
    _noFolding.add(_normalize(name));
  }

  @override
  void clear() {
    _headers.clear();
    _originalNames.clear();
    _noFolding.clear();
    _date = null;
    _expires = null;
    _ifModifiedSince = null;
    _host = null;
    _port = null;
    _contentType = null;
    _contentLength = -1;
    _persistentConnection = true;
    _chunkedTransferEncoding = false;
  }

  String _normalize(String name) {
    if (name.isEmpty) throw ArgumentError('Header name cannot be empty');
    return name.toLowerCase();
  }

  String _valueToString(Object? value) {
    if (value is DateTime) return HttpDate.format(value);
    if (value is HeaderValue) return value.toString();
    if (value is ContentType) return value.toString();
    return value.toString();
  }

  void _updateHostHeader() {
    final hostValue = _host;
    _runWithoutUpdate(() {
      if (hostValue == null || hostValue.isEmpty) {
        _setValues(HttpHeaders.hostHeader, null);
        return;
      }
      final combined = _port != null ? '$hostValue:${_port!}' : hostValue;
      _setValues(HttpHeaders.hostHeader, <String>[combined]);
    });
  }

  void _setValues(String name, List<String>? values) {
    final key = _normalize(name);
    if (values == null || values.isEmpty) {
      _headers.remove(key);
      _originalNames.remove(key);
    } else {
      _headers[key] = List<String>.from(values);
      _originalNames.putIfAbsent(key, () => name);
    }
    if (!_suppressFieldUpdates) _updateComputedFields(key);
  }

  void _runWithoutUpdate(void Function() action) {
    final previous = _suppressFieldUpdates;
    _suppressFieldUpdates = true;
    try {
      action();
    } finally {
      _suppressFieldUpdates = previous;
    }
  }

  void _updateComputedFields(String key) {
    if (_suppressFieldUpdates) return;
    final values = _headers[key];
    switch (key) {
      case HttpHeaders.contentLengthHeader:
        _contentLength = values == null || values.isEmpty
            ? -1
            : int.tryParse(values.last.trim()) ?? -1;
      case HttpHeaders.contentTypeHeader:
        if (values == null || values.isEmpty) {
          _contentType = null;
        } else {
          try {
            _contentType = ContentType.parse(values.last);
          } catch (_) {
            _contentType = null;
          }
        }
      case HttpHeaders.hostHeader:
        if (values == null || values.isEmpty) {
          _host = null;
          _port = null;
        } else {
          final hostValue = values.last;
          final colonIndex = hostValue.lastIndexOf(':');
          if (colonIndex != -1 &&
              colonIndex < hostValue.length - 1 &&
              int.tryParse(hostValue.substring(colonIndex + 1)) != null) {
            _host = hostValue.substring(0, colonIndex);
            _port = int.tryParse(hostValue.substring(colonIndex + 1));
          } else {
            _host = hostValue;
            _port = null;
          }
        }
      case HttpHeaders.dateHeader:
        _date = _parseHttpDate(values);
      case HttpHeaders.expiresHeader:
        _expires = _parseHttpDate(values);
      case HttpHeaders.ifModifiedSinceHeader:
        _ifModifiedSince = _parseHttpDate(values);
      case HttpHeaders.transferEncodingHeader:
        _chunkedTransferEncoding =
            !(values == null) &&
            values.any((value) => value.toLowerCase() == 'chunked');
      case HttpHeaders.connectionHeader:
        if (values == null || values.isEmpty) {
          _persistentConnection = true;
        } else {
          final lowered = values.map((value) => value.toLowerCase());
          if (lowered.contains('close')) {
            _persistentConnection = false;
          } else if (lowered.contains('keep-alive')) {
            _persistentConnection = true;
          }
        }
    }
  }

  DateTime? _parseHttpDate(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    try {
      return HttpDate.parse(values.last);
    } catch (_) {
      return null;
    }
  }
}

/// Marker for synthetic IO types produced by the portable bridge.
///
/// Used so [Request.hasNativeHttpRequest] can distinguish real process sockets
/// from adapter-backed shims.
abstract interface class SyntheticHttpRequest {}

/// Internal capability used by request wrappers to preserve whether the
/// original request came from a portable adapter.
abstract interface class SyntheticRequestCarrier {
  /// Whether the wrapped request is synthetic rather than a native IO request.
  bool get isSyntheticRequest;
}

/// Internal capability used to preserve a textual client address across the
/// portable bridge without requiring `dart:io` socket types.
abstract interface class PortableRemoteAddressCarrier {
  /// Host-provided client address preserved without constructing an
  /// `InternetAddress` on portable runtimes.
  String? get portableRemoteAddress;
}

/// An `HttpRequest` backed by a portable [RequestAdapter].
final class AdapterHttpRequest extends Stream<Uint8List>
    implements
        HttpRequest,
        SyntheticHttpRequest,
        SyntheticRequestCarrier,
        PortableRemoteAddressCarrier,
        HostContextCarrier {
  /// Adapts a [RequestAdapter] to a synthetic `HttpRequest` writing to a
  /// `ResponseAdapter`.
  AdapterHttpRequest(this._adapter, this.response)
    : headers = AdapterHttpHeaders(_adapter.headers),
      requestedUri = _adapter.uri,
      method = _adapter.method {
    final cookieValues = headers[HttpHeaders.cookieHeader];
    if (cookieValues != null) {
      for (final header in cookieValues) {
        for (final part in header.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final idx = trimmed.indexOf('=');
          if (idx == -1) {
            cookies.add(Cookie(trimmed, ''));
          } else {
            cookies.add(
              Cookie(
                trimmed.substring(0, idx).trim(),
                trimmed.substring(idx + 1).trim(),
              ),
            );
          }
        }
      }
    }
  }

  final RequestAdapter _adapter;
  Stream<List<int>>? _listenedBody;

  @override
  Object? get hostContext => _adapter is HostContextCarrier
      ? (_adapter as HostContextCarrier).hostContext
      : null;

  @override
  String? get portableRemoteAddress => _adapter.remoteAddress;

  @override
  bool get isSyntheticRequest => true;

  @override
  final String method;

  @override
  final Uri requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  final AdapterHttpHeaders headers;

  @override
  final List<Cookie> cookies = <Cookie>[];

  @override
  bool get persistentConnection => headers.persistentConnection;

  @override
  final X509Certificate? certificate = null;

  @override
  final HttpSession session = _AdapterSession();

  @override
  String get protocolVersion => '1.1';

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  final HttpResponse response;

  @override
  int get contentLength => headers.contentLength;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _listenedBody ??= _adapter.body;
    return _listenedBody!
        .map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk))
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }
}

/// An `HttpResponse` that writes through a portable [ResponseAdapter].
final class AdapterHttpResponse implements HttpResponse {
  /// Creates an HTTP response backed by a `ResponseAdapter`.
  AdapterHttpResponse(this._adapter) : headers = AdapterHttpHeaders();

  final ResponseAdapter _adapter;
  final Completer<void> _done = Completer<void>();
  final List<Cookie> _cookies = <Cookie>[];
  Encoding _encoding = utf8;
  bool _headersSent = false;
  bool _closed = false;
  int _statusCode = HttpStatus.ok;

  @override
  AdapterHttpHeaders headers;

  @override
  int get contentLength => headers.contentLength;

  @override
  set contentLength(int value) => headers.contentLength = value;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) {
    _statusCode = value;
    if (!_headersSent) {
      _adapter.statusCode = value;
    }
  }

  @override
  String reasonPhrase = 'OK';

  @override
  bool persistentConnection = true;

  @override
  Duration? deadline;

  @override
  bool bufferOutput = true;

  @override
  List<Cookie> get cookies => _cookies;

  void _ensureHeadersSent() {
    if (_headersSent) return;
    _adapter.statusCode = _statusCode;
    headers.forEach((name, values) {
      if (name.toLowerCase() == HttpHeaders.setCookieHeader) {
        for (final v in values) {
          _adapter.addHeader(name, v);
        }
      } else {
        _adapter.setHeader(name, values.join(', '));
      }
    });
    for (final cookie in _cookies) {
      _adapter.addHeader(HttpHeaders.setCookieHeader, cookie.toString());
    }
    _headersSent = true;
  }

  @override
  void add(List<int> data) {
    _ensureHeadersSent();
    if (_closed) throw StateError('Response is already closed');
    _adapter.write(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ensureHeadersSent();
    await _adapter.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) => _encoding = value;

  @override
  void write(Object? object) => add(encoding.encode(object?.toString() ?? ''));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  Future<void> flush() async {
    _ensureHeadersSent();
    await _adapter.flush();
  }

  @override
  Future<void> redirect(
    Uri location, {
    int status = HttpStatus.movedTemporarily,
  }) {
    headers.set(HttpHeaders.locationHeader, location.toString());
    statusCode = status;
    return close();
  }

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) =>
      throw UnsupportedError(
        'detachSocket is not supported on portable adapter responses',
      );
}

final class _AdapterSession extends MapBase<dynamic, dynamic>
    implements HttpSession {
  @override
  String id = '';

  @override
  bool isNew = true;

  final Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void destroy() => _data.clear();

  @override
  set onTimeout(void Function() callback) {}

  @override
  dynamic operator [](Object? key) => key is String ? _data[key] : null;

  @override
  void clear() => _data.clear();

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  void operator []=(Object? key, dynamic value) {
    if (key is! String) throw ArgumentError('Session keys must be strings');
    _data[key] = value;
  }

  @override
  dynamic remove(Object? key) => key is String ? _data.remove(key) : null;
}
