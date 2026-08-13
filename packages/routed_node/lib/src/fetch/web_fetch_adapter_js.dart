import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import '../runtime/runtime.dart';
import 'fetch_exchange.dart';
import 'web_stream_bridge.dart';

/// Adapts a native Fetch request to the shared Fetch view.
final class WebFetchRequest implements FetchRequestView {
  WebFetchRequest(
    this.request, {
    required RoutedNodeContext hostContext,
    Future<FetchWebSocketUpgrade> Function()? acceptWebSocket,
  }) : _hostContext = hostContext,
       _acceptWebSocket =
           request.headers.get('upgrade')?.toLowerCase() == 'websocket'
           ? acceptWebSocket
           : null;

  final web.Request request;
  final Future<FetchWebSocketUpgrade> Function()? _acceptWebSocket;
  final RoutedNodeContext _hostContext;

  @override
  String get method => request.method;

  @override
  String get url => request.url;

  @override
  Map<String, Object?> get rawHeaders {
    final headers = <String, Object?>{};
    final object = globalContext.getProperty('Object'.toJS);
    if (object == null || !object.isA<JSObject>()) return headers;
    final keys = (object as JSObject).getProperty('keys'.toJS);
    if (keys == null || !keys.isA<JSFunction>()) return headers;
    final result = (keys as JSFunction).callAsFunction(object, request.headers);
    if (result == null || !result.isA<JSArray>()) return headers;
    final list = result as JSArray;
    for (var i = 0; i < list.length; i++) {
      final key = list.getProperty(i.toJS);
      if (key != null) {
        final name = key.toString();
        headers[name] = request.headers.get(name);
      }
    }
    return headers;
  }

  @override
  Stream<List<int>> get body {
    final stream = request.body;
    return stream == null ? const Stream.empty() : dartStreamFromWeb(stream);
  }

  @override
  String? get remoteAddress => null;

  @override
  RoutedNodeContext get hostContext => _hostContext;

  Future<FetchWebSocketUpgrade> Function()? get acceptWebSocket =>
      _acceptWebSocket;
}

/// Response adapter that starts a native Fetch response before the body ends.
///
/// Headers are released once Routed has committed them; body chunks continue
/// through the returned native `ReadableStream`.
final class WebStreamingResponseAdapter
    implements ResponseAdapter, WebSocketResponseAdapter {
  WebStreamingResponseAdapter() : _body = StreamController<List<int>>();

  final StreamController<List<int>> _body;
  final Completer<void> _headersReady = Completer<void>();
  final Map<String, List<String>> _headers = <String, List<String>>{};
  int _statusCode = 200;
  bool _headersSent = false;
  bool _closed = false;
  Object? _upgradeResponse;

  Object? get upgradeResponse => _upgradeResponse;

  int get statusCodeValue => _statusCode;
  Map<String, List<String>> get headersValue => _headers;
  Stream<List<int>> get body => _body.stream;
  Future<void> get headersReady => _headersReady.future;

  void _markHeadersReady() {
    if (_headersSent) return;
    _headersSent = true;
    if (!_headersReady.isCompleted) _headersReady.complete();
  }

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) {
    if (!_headersSent) _statusCode = value;
  }

  @override
  void setHeader(String name, String value) {
    if (_headersSent) return;
    _headers[name] = <String>[value];
  }

  @override
  void addHeader(String name, String value) {
    if (_headersSent) return;
    _headers.putIfAbsent(name, () => <String>[]).add(value);
  }

  @override
  void write(List<int> bytes) {
    if (_closed) throw StateError('Cannot write to a closed Fetch response');
    _markHeadersReady();
    if (bytes.isNotEmpty) _body.add(bytes);
  }

  @override
  Future<void> flush() async {
    _markHeadersReady();
  }

  @override
  void upgrade(Object nativeWebSocketResponse) {
    _upgradeResponse = nativeWebSocketResponse;
    _markHeadersReady();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _markHeadersReady();
    await _body.close();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    _statusCode = 500;
    _headers['content-type'] = <String>['text/plain; charset=utf-8'];
    _markHeadersReady();
    _body.addError(error, stackTrace);
    unawaited(_body.close());
  }
}

/// Converts a buffered/streaming Routed response view into a native Fetch response.
web.Response webResponseFromFetchView(FetchResponseView source) {
  final headers = web.Headers();
  source.headers.forEach((name, values) {
    for (final value in values) {
      headers.append(name, value);
    }
  });
  return web.Response(
    webStreamFromDart(source.body),
    web.ResponseInit(status: source.statusCode, headers: headers),
  );
}

/// Converts a streaming response adapter into a native Fetch response.
web.Response webResponseFromStreamingAdapter(
  WebStreamingResponseAdapter source,
) {
  final upgrade = source.upgradeResponse;
  if (upgrade != null) {
    final init = web.ResponseInit(status: 101)
      ..setProperty('webSocket'.toJS, upgrade as JSAny);
    return web.Response(null, init);
  }
  final headers = web.Headers();
  source.headersValue.forEach((name, values) {
    for (final value in values) {
      headers.append(name, value);
    }
  });
  return web.Response(
    webStreamFromDart(source.body),
    web.ResponseInit(status: source.statusCodeValue, headers: headers),
  );
}
