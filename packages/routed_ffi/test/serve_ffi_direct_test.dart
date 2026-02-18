import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_ffi/routed_ffi.dart';
import 'package:test/test.dart';

final class _RunningDirectServer {
  _RunningDirectServer({
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

Future<_RunningDirectServer> _startDirectServer(
  FfiDirectHandler handler,
) async {
  final shutdown = Completer<void>();
  final port = await _reservePort();
  final serveFuture = serveFfiDirect(
    handler,
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    echo: false,
    http3: false,
    shutdownSignal: shutdown.future,
  );

  final baseUri = Uri.parse('http://127.0.0.1:$port');
  await _waitUntilUp(baseUri.replace(path: '/'));
  return _RunningDirectServer(
    baseUri: baseUri,
    shutdown: shutdown,
    serveFuture: serveFuture,
  );
}

Future<void> _stopDirectServer(_RunningDirectServer running) async {
  if (!running.shutdown.isCompleted) {
    running.shutdown.complete();
  }
  await running.serveFuture.timeout(const Duration(seconds: 5));
}

void main() {
  test(
    'serveFfiDirect handles request fields and returns bytes response',
    () async {
      final running = await _startDirectServer((request) async {
        final bodyText = await utf8.decoder.bind(request.body).join();
        return FfiDirectResponse.bytes(
          headers: const <MapEntry<String, String>>[
            MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
          ],
          bodyBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'method': request.method,
                'path': request.path,
                'query': request.query,
                'header': request.header('x-test'),
                'body': bodyText,
              }),
            ),
          ),
        );
      });

      final client = HttpClient();
      try {
        final uri = running.baseUri.replace(
          path: '/echo',
          queryParameters: <String, String>{'q': '1'},
        );
        final req = await client.postUrl(uri);
        req.headers.set('x-test', 'direct');
        req.add(utf8.encode('hello ffi direct'));
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(body), <String, Object?>{
          'method': 'POST',
          'path': '/echo',
          'query': 'q=1',
          'header': 'direct',
          'body': 'hello ffi direct',
        });
      } finally {
        client.close(force: true);
      }

      await _stopDirectServer(running);
    },
  );

  test('serveFfiDirect supports streaming responses', () async {
    final running = await _startDirectServer((request) async {
      var requestBytes = 0;
      await for (final chunk in request.body) {
        requestBytes += chunk.length;
      }
      return FfiDirectResponse.stream(
        status: HttpStatus.created,
        headers: <MapEntry<String, String>>[
          const MapEntry(HttpHeaders.contentTypeHeader, 'text/plain'),
          MapEntry('x-request-bytes', '$requestBytes'),
        ],
        body: Stream<Uint8List>.fromIterable(<Uint8List>[
          Uint8List.fromList(<int>[97, 98]),
          Uint8List.fromList(<int>[99, 100]),
        ]),
      );
    });

    final client = HttpClient();
    try {
      final uri = running.baseUri.replace(path: '/stream');
      final req = await client.postUrl(uri);
      await req.addStream(
        Stream<List<int>>.fromIterable(<List<int>>[
          utf8.encode('hello'),
          utf8.encode('world'),
        ]),
      );
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.created);
      expect(res.headers.value('x-request-bytes'), '10');
      expect(body, 'abcd');
    } finally {
      client.close(force: true);
    }

    await _stopDirectServer(running);
  });

  test('serveFfiDirect maps handler exception to 500 response', () async {
    final running = await _startDirectServer((_) async {
      throw StateError('boom');
    });

    final client = HttpClient();
    try {
      final uri = running.baseUri.replace(path: '/fail');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.internalServerError);
      expect(body, contains('direct handler error: Bad state: boom'));
    } finally {
      client.close(force: true);
    }

    await _stopDirectServer(running);
  });
}
