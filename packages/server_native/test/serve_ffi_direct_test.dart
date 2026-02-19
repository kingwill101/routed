import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';
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
  NativeDirectHandler handler, {
  bool nativeDirect = false,
}) async {
  final shutdown = Completer<void>();
  final port = await _reservePort();
  final serveFuture = serveNativeDirect(
    handler,
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    echo: false,
    http3: false,
    nativeDirect: nativeDirect,
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
    'serveNativeDirect handles request fields and returns bytes response',
    () async {
      final running = await _startDirectServer((request) async {
        final bodyText = await utf8.decoder.bind(request.body).join();
        return NativeDirectResponse.bytes(
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

  test('serveNativeDirect supports streaming responses', () async {
    final running = await _startDirectServer((request) async {
      var requestBytes = 0;
      await for (final chunk in request.body) {
        requestBytes += chunk.length;
      }
      return NativeDirectResponse.stream(
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

  test('serveNativeDirect supports pre-encoded static responses', () async {
    final staticResponse = NativeDirectResponse.preEncodedBytes(
      headers: const <MapEntry<String, String>>[
        MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
      ],
      bodyBytes: Uint8List.fromList(
        utf8.encode('{"ok":true,"mode":"pre_encoded"}'),
      ),
    );
    final running = await _startDirectServer((_) async => staticResponse);

    final client = HttpClient();
    try {
      final uri = running.baseUri.replace(path: '/pre-encoded');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'application/json');
      expect(jsonDecode(body), <String, Object?>{
        'ok': true,
        'mode': 'pre_encoded',
      });
    } finally {
      client.close(force: true);
    }

    await _stopDirectServer(running);
  });

  test(
    'serveNativeDirect nativeDirect callback mode supports streaming request/response',
    () async {
      final running = await _startDirectServer((request) async {
        var requestBytes = 0;
        await for (final chunk in request.body) {
          requestBytes += chunk.length;
        }
        return NativeDirectResponse.stream(
          status: HttpStatus.accepted,
          headers: <MapEntry<String, String>>[
            const MapEntry(HttpHeaders.contentTypeHeader, 'text/plain'),
            MapEntry('x-request-bytes', '$requestBytes'),
          ],
          body: Stream<Uint8List>.fromIterable(<Uint8List>[
            Uint8List.fromList(utf8.encode('stream-')),
            Uint8List.fromList(utf8.encode('ok')),
          ]),
        );
      }, nativeDirect: true);

      final client = HttpClient();
      try {
        final uri = running.baseUri.replace(path: '/native-stream');
        final req = await client.postUrl(uri);
        await req.addStream(
          Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode('hello'),
            utf8.encode('world'),
          ]),
        );
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.accepted);
        expect(res.headers.value('x-request-bytes'), '10');
        expect(body, 'stream-ok');
      } finally {
        client.close(force: true);
      }

      await _stopDirectServer(running);
    },
  );

  test('serveNativeDirect maps handler exception to 500 response', () async {
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

  test(
    'serveNativeDirect nativeDirect callback mode handles request/response',
    () async {
      final running = await _startDirectServer((request) async {
        final bodyText = await utf8.decoder.bind(request.body).join();
        return NativeDirectResponse.bytes(
          headers: const <MapEntry<String, String>>[
            MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
          ],
          bodyBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'method': request.method,
                'path': request.path,
                'body': bodyText,
              }),
            ),
          ),
        );
      }, nativeDirect: true);

      final client = HttpClient();
      try {
        final uri = running.baseUri.replace(path: '/native-direct');
        final req = await client.postUrl(uri);
        req.add(utf8.encode('native direct body'));
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(body), <String, Object?>{
          'method': 'POST',
          'path': '/native-direct',
          'body': 'native direct body',
        });
      } finally {
        client.close(force: true);
      }

      await _stopDirectServer(running);
    },
  );
}
