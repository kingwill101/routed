import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'package:routed_node/bun.dart';
import 'package:routed_node_api_sample/app.dart';

Future<void> main() async {
  final engine = await createEngine();
  final handle = await serveBun(engine, host: '127.0.0.1', port: 0);
  try {
    final health = await _get(handle.port, '/health');
    _expect(health.status, 200, 'GET /health');
    final healthJson = jsonDecode(health.body) as Map<String, dynamic>;
    _expect(healthJson['ok'], true, 'health response');

    final capabilities = await _get(handle.port, '/capabilities');
    _expect(capabilities.status, 200, 'GET /capabilities');
    final capabilityJson =
        jsonDecode(capabilities.body) as Map<String, dynamic>;
    _expect(capabilityJson['bun']['streaming'], true, 'Bun streaming');
    _expect(capabilityJson['bun']['webSocket'], true, 'Bun WebSocket flag');

    final socket = web.WebSocket('ws://127.0.0.1:${handle.port}/ws');
    final echoed = Completer<void>();
    socket.onopen = (() => socket.send('hello'.toJS)).toJS;
    socket.onmessage = ((JSAny event) {
      final data = (event as JSObject).getProperty('data'.toJS);
      if (data != null &&
          data.isA<JSString>() &&
          (data as JSString).toDart == 'echo:hello' &&
          !echoed.isCompleted) {
        echoed.complete();
      }
    }).toJS;
    await echoed.future.timeout(const Duration(seconds: 5));
    socket.close();

    final echo = await _post(handle.port, '/echo', '{"ok":true}');
    _expect(echo.status, 200, 'POST /echo');
    final echoJson = jsonDecode(echo.body) as Map<String, dynamic>;
    _expect(echoJson['body'], '{"ok":true}', 'echo request body');

    // ignore: avoid_print
    print('bun integration ok');
  } finally {
    await handle.close(force: true);
    await engine.close();
  }
}

Future<({int status, String body})> _get(int port, String path) {
  return _request('GET', port, path);
}

Future<({int status, String body})> _post(int port, String path, String body) {
  return _request('POST', port, path, body: body);
}

Future<({int status, String body})> _request(
  String method,
  int port,
  String path, {
  String? body,
}) async {
  final fetch = globalContext.getProperty('fetch'.toJS);
  if (fetch == null || !fetch.isA<JSFunction>()) {
    throw StateError('Bun global fetch is unavailable');
  }
  final init = JSObject()
    ..setProperty('method'.toJS, method.toJS)
    ..setProperty(
      'headers'.toJS,
      JSObject()..setProperty('content-type'.toJS, 'application/json'.toJS),
    );
  if (body != null) init.setProperty('body'.toJS, body.toJS);

  final result = (fetch as JSFunction).callAsFunction(
    null,
    'http://127.0.0.1:$port$path'.toJS,
    init,
  );
  final response = await (result as JSPromise<JSAny?>).toDart as JSObject;
  final status = (response.getProperty('status'.toJS) as JSNumber).toDartInt;
  final text = response.getProperty('text'.toJS) as JSFunction;
  final textResult = text.callAsFunction(response);
  final responseBody =
      await (textResult as JSPromise<JSAny?>).toDart as JSString;
  return (status: status, body: responseBody.toDart);
}

void _expect(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
}
