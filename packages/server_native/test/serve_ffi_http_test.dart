import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_native/server_native.dart';
import 'package:server_native/src/bridge/bridge_runtime.dart';
import 'package:test/test.dart';

final class _RunningHttpBridgeServer {
  _RunningHttpBridgeServer({
    required this.baseUri,
    required this.shutdown,
    required this.serveFuture,
  });

  final Uri baseUri;
  final Completer<void> shutdown;
  final Future<void> serveFuture;
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitUntilUp(Uri uri) async {
  final client = HttpClient();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        await res.drain<void>();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('Timed out waiting for $uri to become reachable');
  } finally {
    client.close(force: true);
  }
}

Future<_RunningHttpBridgeServer> _startHttpBridgeServer(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool nativeCallback = false,
}) async {
  final shutdown = Completer<void>();
  final port = await _reservePort();
  final serveFuture = serveNativeHttp(
    handler,
    host: host,
    port: port,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    echo: false,
    http3: false,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdown.future,
  );

  final baseUri = Uri.parse('http://127.0.0.1:$port');
  await _waitUntilUp(baseUri.replace(path: '/'));
  return _RunningHttpBridgeServer(
    baseUri: baseUri,
    shutdown: shutdown,
    serveFuture: serveFuture,
  );
}

Future<void> _stopServer(_RunningHttpBridgeServer running) async {
  if (!running.shutdown.isCompleted) {
    running.shutdown.complete();
  }
  await running.serveFuture.timeout(const Duration(seconds: 5));
}

void main() {
  test('serveNativeHttp exposes bridge as HttpServer-style handler', () async {
    final running = await _startHttpBridgeServer((request) async {
      final requestBody = await utf8.decoder.bind(request).join();
      request.response.statusCode = HttpStatus.created;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.response.headers.set('x-method', request.method);
      request.response.write(
        jsonEncode(<String, Object?>{
          'path': request.uri.path,
          'query': request.uri.query,
          'body': requestBody,
        }),
      );
      await request.response.close();
    });

    final client = HttpClient();
    try {
      final uri = running.baseUri.replace(
        path: '/http-bridge',
        queryParameters: <String, String>{'q': '1'},
      );
      final req = await client.postUrl(uri);
      req.add(utf8.encode('hello http bridge'));
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.created);
      expect(res.headers.value('x-method'), 'POST');
      expect(jsonDecode(body), <String, Object?>{
        'path': '/http-bridge',
        'query': 'q=1',
        'body': 'hello http bridge',
      });
    } finally {
      client.close(force: true);
    }

    await _stopServer(running);
  });

  test(
    'serveNativeHttp keeps HttpRequest compatibility with nativeCallback',
    () async {
      final running = await _startHttpBridgeServer((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.accepted;
        request.response.headers.set('x-runtime', 'native-callback');
        request.response.write(
          jsonEncode(<String, Object?>{
            'method': request.method,
            'path': request.uri.path,
            'body': requestBody,
          }),
        );
        await request.response.close();
      }, nativeCallback: true);

      final client = HttpClient();
      try {
        final req = await client.postUrl(
          running.baseUri.replace(path: '/native-http'),
        );
        req.add(utf8.encode('native callback body'));
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.accepted);
        expect(res.headers.value('x-runtime'), 'native-callback');
        expect(jsonDecode(body), <String, Object?>{
          'method': 'POST',
          'path': '/native-http',
          'body': 'native callback body',
        });
      } finally {
        client.close(force: true);
      }

      await _stopServer(running);
    },
  );

  test('serveNativeHttp accepts HttpServer-like bind options', () async {
    final running = await _startHttpBridgeServer(
      (request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('ok');
        await request.response.close();
      },
      host: InternetAddress.loopbackIPv4,
      backlog: 128,
      v6Only: false,
      shared: true,
    );

    final client = HttpClient();
    try {
      final res = await (await client.getUrl(
        running.baseUri.replace(path: '/'),
      )).close();
      expect(res.statusCode, HttpStatus.ok);
      expect(await utf8.decodeStream(res), 'ok');
    } finally {
      client.close(force: true);
    }

    await _stopServer(running);
  });

  test('serveNativeHttp supports WebSocket upgrade', () async {
    final running = await _startHttpBridgeServer((request) async {
      if (request.uri.path == '/ws') {
        final webSocket = await WebSocketTransformer.upgrade(request);
        webSocket.listen(
          (message) => webSocket.add('echo:$message'),
          onDone: () => webSocket.close(),
          cancelOnError: false,
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final wsUri = running.baseUri.replace(scheme: 'ws', path: '/ws');
    final webSocket = await WebSocket.connect(wsUri.toString());
    try {
      webSocket.add('ping');
      final firstMessage = await webSocket.first.timeout(
        const Duration(seconds: 3),
      );
      expect(firstMessage, 'echo:ping');
      await webSocket.close();
    } finally {
      await webSocket.close();
    }

    await _stopServer(running);
  });

  test(
    'serveNativeHttp supports WebSocket upgrade with nativeCallback',
    () async {
      final running = await _startHttpBridgeServer((request) async {
        if (request.uri.path == '/ws') {
          final webSocket = await WebSocketTransformer.upgrade(request);
          webSocket.listen(
            (message) => webSocket.add('echo:$message'),
            onDone: () => webSocket.close(),
            cancelOnError: false,
          );
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }, nativeCallback: true);

      final wsUri = running.baseUri.replace(scheme: 'ws', path: '/ws');
      final webSocket = await WebSocket.connect(wsUri.toString());
      try {
        webSocket.add('ping');
        final firstMessage = await webSocket.first.timeout(
          const Duration(seconds: 3),
        );
        expect(firstMessage, 'echo:ping');
        await webSocket.close();
      } finally {
        await webSocket.close();
      }

      await _stopServer(running);
    },
  );
}
