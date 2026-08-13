import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../runtime/runtime.dart';
import 'fetch_exchange.dart';
import 'web_stream_bridge.dart';

/// Typed host extension for Fetch-compatible runtimes.
final class FetchRuntimeExtension implements RoutedNodeExtension {
  const FetchRuntimeExtension({
    required this.runtime,
    this.request,
    this.executionContext,
    this.environment,
  });

  @override
  final RoutedNodeRuntime runtime;
  final web.Request? request;
  final Object? executionContext;
  final Object? environment;
}

/// Adapts a native Fetch request to the shared Fetch view.
final class WebFetchRequest implements FetchRequestView {
  WebFetchRequest(this.request, {required RoutedNodeContext hostContext})
    : _hostContext = hostContext;

  final web.Request request;
  final RoutedNodeContext _hostContext;

  @override
  String get method => request.method;

  @override
  String get url => request.url;

  @override
  Map<String, Object?> get rawHeaders {
    final headers = <String, Object?>{};
    final keys = globalContext.getProperty('Object'.toJS);
    if (keys == null || !keys.isA<JSObject>()) return headers;
    final keysFn = (keys as JSObject).getProperty('keys'.toJS);
    if (keysFn == null || !keysFn.isA<JSFunction>()) return headers;
    final result = (keysFn as JSFunction).callAsFunction(keys, request.headers);
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
}

/// Converts a Routed response view into a native Fetch response.
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
