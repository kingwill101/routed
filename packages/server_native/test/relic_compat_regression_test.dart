import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart' as relic;
import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

enum _Backend {
  dartIo('dart:io'),
  native('server_native');

  const _Backend(this.label);
  final String label;
}

Future<HttpServer> _bindHttpServer(_Backend backend) {
  switch (backend) {
    case _Backend.dartIo:
      return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    case _Backend.native:
      return NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
        nativeCallback: true,
      );
  }
}

Future<HttpServer> _startHttpServer(
  _Backend backend,
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await _bindHttpServer(backend);
  // ignore: discarded_futures
  server.listen((request) async {
    await handler(request);
  });
  return server;
}

Future<relic.RelicServer> _startRelicServer(
  _Backend backend,
  relic.Handler handler,
) async {
  final server = relic.RelicServer(
    () async => IOAdapter(await _bindHttpServer(backend)),
    noOfIsolates: 1,
  );
  await server.mountAndStart(handler);
  return server;
}

Future<void> _respondOk(HttpRequest request, {String body = 'ok'}) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..write(body);
  await request.response.close();
}

Future<(int statusCode, String body)> _runInvalidTransferEncoding(
  _Backend backend,
) async {
  final server = await _startHttpServer(
    backend,
    (request) => _respondOk(request),
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    request.headers.set(HttpHeaders.transferEncodingHeader, 'custom-value');
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}

Future<int> _runConnectionsInfo(_Backend backend) async {
  final release = Completer<void>();
  var started = 0;
  final allStarted = Completer<void>();

  final server = await _startHttpServer(backend, (request) async {
    started++;
    if (started == 2 && !allStarted.isCompleted) {
      allStarted.complete();
    }
    await release.future;
    await _respondOk(request, body: 'done');
  });

  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:${server.port}/');
    final responseFutures = <Future<HttpClientResponse>>[
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
    ];

    await allStarted.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final info =
        server.connectionsInfo().active + server.connectionsInfo().idle;

    release.complete();
    final responses = await Future.wait(responseFutures);
    for (final response in responses) {
      await response.drain<void>();
    }
    return info;
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}

Future<Object> _statusOrError(Future<HttpClientResponse> responseFuture) async {
  try {
    final response = await responseFuture;
    final statusCode = response.statusCode;
    await response.drain<void>();
    return statusCode;
  } catch (error) {
    return error.runtimeType.toString();
  }
}

Future<List<Object>> _runGracefulClose(_Backend backend) async {
  final release = Completer<void>();
  var started = 0;
  final allStarted = Completer<void>();

  final server = await _startHttpServer(backend, (request) async {
    started++;
    if (started == 2 && !allStarted.isCompleted) {
      allStarted.complete();
    }
    await release.future;
    await _respondOk(request, body: 'completed');
  });

  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:${server.port}/');
    final responseFutures = <Future<HttpClientResponse>>[
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
    ];

    await allStarted.future.timeout(const Duration(seconds: 3));
    final closeFuture = server.close();
    release.complete();
    final outcomes = await Future.wait(responseFutures.map(_statusOrError));
    await closeFuture.timeout(const Duration(seconds: 3));
    return outcomes;
  } finally {
    client.close(force: true);
    try {
      await server.close(force: true);
    } catch (_) {}
  }
}

Future<Object> _runWebSocketPingInterval(_Backend backend) async {
  const pingInterval = Duration(milliseconds: 5);
  const idleDelay = Duration(milliseconds: 15);

  final server = await _startHttpServer(backend, (request) async {
    final webSocket = await WebSocketTransformer.upgrade(request);
    webSocket.pingInterval = pingInterval;
    await for (final event in webSocket) {
      if (event is! String) {
        continue;
      }
      await Future<void>.delayed(idleDelay);
      webSocket.add('tock');
    }
  });

  final clientWebSocket = await WebSocket.connect(
    'ws://127.0.0.1:${server.port}',
  );
  try {
    await Future<void>.delayed(idleDelay);
    clientWebSocket.add('tick');
    final message = await clientWebSocket.first.timeout(
      const Duration(seconds: 3),
    );
    return message;
  } catch (error) {
    return error.runtimeType.toString();
  } finally {
    try {
      await clientWebSocket.close();
    } catch (_) {}
    await server.close(force: true);
  }
}

Future<String> _runBadHostRaw(_Backend backend) async {
  final server = await _startHttpServer(
    backend,
    (request) => _respondOk(request),
  );
  final socket = await Socket.connect('127.0.0.1', server.port);
  try {
    socket.add(
      ascii.encode(
        'GET / HTTP/1.1\r\n'
        'Host: ^^super bad !@#host\r\n'
        'Connection: close\r\n'
        '\r\n',
      ),
    );
    await socket.flush();
    return utf8.decode(
      await socket.fold<List<int>>(<int>[], (a, b) => a..addAll(b)),
    );
  } finally {
    await socket.close();
    await server.close(force: true);
  }
}

Future<String> _runSoftInvalidHostRaw(_Backend backend) async {
  final server = await _startHttpServer(
    backend,
    (request) => _respondOk(request),
  );
  final socket = await Socket.connect('127.0.0.1', server.port);
  try {
    socket.add(
      ascii.encode(
        'GET / HTTP/1.1\r\n'
        'Host: http://example.com\r\n'
        'Connection: close\r\n'
        '\r\n',
      ),
    );
    await socket.flush();
    return utf8.decode(
      await socket.fold<List<int>>(<int>[], (a, b) => a..addAll(b)),
    );
  } finally {
    await socket.close();
    await server.close(force: true);
  }
}

int _extractRawStatusCode(String rawResponse) {
  final firstLineEnd = rawResponse.indexOf('\r\n');
  if (firstLineEnd == -1) {
    throw StateError('missing HTTP status line');
  }
  final statusLine = rawResponse.substring(0, firstLineEnd);
  final parts = statusLine.split(' ');
  if (parts.length < 2) {
    throw StateError('invalid HTTP status line: $statusLine');
  }
  return int.parse(parts[1]);
}

Future<int> _runRelicConnectionsInfo(_Backend backend) async {
  final release = Completer<void>();
  var started = 0;
  final allStarted = Completer<void>();
  final server = await _startRelicServer(backend, (_) async {
    started++;
    if (started == 2 && !allStarted.isCompleted) {
      allStarted.complete();
    }
    await release.future;
    return relic.Response.ok(body: relic.Body.fromString('done'));
  });

  final client = HttpClient();
  try {
    final uri = Uri.http('localhost:${server.port}');
    final responses = <Future<HttpClientResponse>>[
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
      () async {
        final req = await client.getUrl(uri);
        return req.close();
      }(),
    ];
    await allStarted.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final info = await server.connectionsInfo();
    release.complete();
    await Future.wait(responses.map((r) async => (await r).drain<void>()));
    return info.active + info.idle;
  } finally {
    client.close(force: true);
    await server.close();
  }
}

void main() {
  group('Relic Compatibility A/B (dart:io baseline)', () {
    test('invalid Transfer-Encoding passthrough parity', () async {
      final dartIo = await _runInvalidTransferEncoding(_Backend.dartIo);
      final native = await _runInvalidTransferEncoding(_Backend.native);

      expect(dartIo.$1, HttpStatus.ok);
      expect(native, dartIo);
    });

    test('connectionsInfo in-flight parity', () async {
      final dartIo = await _runConnectionsInfo(_Backend.dartIo);
      final native = await _runConnectionsInfo(_Backend.native);

      expect(dartIo, 2);
      expect(native, dartIo);
    });

    test('graceful close parity', () async {
      final dartIo = await _runGracefulClose(_Backend.dartIo);
      final native = await _runGracefulClose(_Backend.native);

      expect(dartIo, <Object>[HttpStatus.ok, HttpStatus.ok]);
      expect(native, dartIo);
    });

    test('websocket ping-interval parity', () async {
      final dartIo = await _runWebSocketPingInterval(_Backend.dartIo);
      final native = await _runWebSocketPingInterval(_Backend.native);

      expect(native, dartIo);
    });

    test('bad host handling parity', () async {
      final dartIo = await _runBadHostRaw(_Backend.dartIo);
      final native = await _runBadHostRaw(_Backend.native);

      expect(_extractRawStatusCode(native), _extractRawStatusCode(dartIo));
    });

    test('soft-invalid host handling parity', () async {
      final dartIo = await _runSoftInvalidHostRaw(_Backend.dartIo);
      final native = await _runSoftInvalidHostRaw(_Backend.native);

      expect(_extractRawStatusCode(native), _extractRawStatusCode(dartIo));
    });

    test('relic adapter connectionsInfo parity', () async {
      final dartIo = await _runRelicConnectionsInfo(_Backend.dartIo);
      final native = await _runRelicConnectionsInfo(_Backend.native);

      expect(dartIo, 2);
      expect(native, dartIo);
    });
  });
}
