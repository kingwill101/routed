// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_ffi/src/bridge/bridge_runtime.dart';
import 'package:routed_ffi/src/native/routed_ffi_native.dart';
import 'package:test/test.dart';

final class _ProxyHarness {
  _ProxyHarness({
    required this.proxy,
    required this.bridgeServer,
    required this.bridgeSubscription,
    required this.baseUri,
  });

  final NativeProxyServer proxy;
  final ServerSocket bridgeServer;
  final StreamSubscription<Socket> bridgeSubscription;
  final Uri baseUri;

  Future<void> close() async {
    proxy.close();
    await bridgeSubscription.cancel();
    await bridgeServer.close();
  }
}

Future<_ProxyHarness> _startProxyHarness(
  Future<void> Function(Socket socket) onSocket,
) async {
  final bridge = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = bridge.listen((socket) {
    // ignore: discarded_futures
    onSocket(socket);
  });

  final proxy = NativeProxyServer.start(
    host: InternetAddress.loopbackIPv4.address,
    port: 0,
    backendHost: InternetAddress.loopbackIPv4.address,
    backendPort: bridge.port,
  );

  return _ProxyHarness(
    proxy: proxy,
    bridgeServer: bridge,
    bridgeSubscription: subscription,
    baseUri: Uri.parse('http://127.0.0.1:${proxy.port}'),
  );
}

Future<(int status, String body)> _requestText(Uri uri) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    return (res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

Future<void> _writeFramedPayload(Socket socket, List<int> payload) async {
  final header = Uint8List(4)
    ..[0] = (payload.length >> 24) & 0xff
    ..[1] = (payload.length >> 16) & 0xff
    ..[2] = (payload.length >> 8) & 0xff
    ..[3] = payload.length & 0xff;
  socket
    ..add(header)
    ..add(payload);
  await socket.flush();
}

Future<void> _writeFramedPayloads(
  Socket socket,
  Iterable<List<int>> payloads,
) async {
  for (final payload in payloads) {
    final header = Uint8List(4)
      ..[0] = (payload.length >> 24) & 0xff
      ..[1] = (payload.length >> 16) & 0xff
      ..[2] = (payload.length >> 8) & 0xff
      ..[3] = payload.length & 0xff;
    socket
      ..add(header)
      ..add(payload);
  }
  await socket.flush();
}

Uint8List _encodedResponsePayload({required int status, List<int>? bodyBytes}) {
  return BridgeResponseFrame(
    status: status,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(bodyBytes ?? const <int>[]),
  ).encodePayload();
}

List<Uint8List> _encodedChunkedResponsePayloads({
  required int status,
  List<int>? bodyBytes,
}) {
  return <Uint8List>[
    BridgeResponseFrame(
      status: status,
      headers: const <MapEntry<String, String>>[],
      bodyBytes: Uint8List(0),
    ).encodeStartPayload(),
    if (bodyBytes != null && bodyBytes.isNotEmpty)
      BridgeResponseFrame.encodeChunkPayload(bodyBytes),
    BridgeResponseFrame.encodeEndPayload(),
  ];
}

void main() {
  test('serves static response in native direct benchmark mode', () async {
    final proxy = NativeProxyServer.start(
      host: InternetAddress.loopbackIPv4.address,
      port: 0,
      backendHost: InternetAddress.loopbackIPv4.address,
      backendPort: 9,
      benchmarkMode: 1,
    );
    addTearDown(proxy.close);

    final uri = Uri.parse('http://127.0.0.1:${proxy.port}/bench');
    final (status, body) = await _requestText(uri);
    expect(status, HttpStatus.ok);
    expect(jsonDecode(body), <String, Object?>{
      'ok': true,
      'label': 'routed_ffi_native_direct',
    });
  });

  test('returns 502 when bridge closes without response', () async {
    final harness = await _startProxyHarness((socket) async {
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, body) = await _requestText(
      harness.baseUri.replace(path: '/'),
    );
    expect(status, HttpStatus.badGateway);
    expect(body, contains('bridge call failed'));
  });

  test('returns 502 when bridge responds with invalid frame payload', () async {
    final harness = await _startProxyHarness((socket) async {
      await _writeFramedPayload(socket, const <int>[1, 2, 3]);
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, body) = await _requestText(
      harness.baseUri.replace(path: '/'),
    );
    expect(status, HttpStatus.badGateway);
    expect(body, contains('decode response failed'));
  });

  test('returns 502 when bridge responds with wrong frame type', () async {
    final harness = await _startProxyHarness((socket) async {
      final payload = BridgeRequestFrame(
        method: 'GET',
        scheme: 'http',
        authority: '127.0.0.1',
        path: '/',
        query: '',
        protocol: '1.1',
        headers: const <MapEntry<String, String>>[],
        bodyBytes: Uint8List(0),
      ).encodePayload();
      await _writeFramedPayload(socket, payload);
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, body) = await _requestText(
      harness.baseUri.replace(path: '/'),
    );
    expect(status, HttpStatus.badGateway);
    expect(body, contains('invalid bridge response frame type'));
  });

  test('returns 502 when bridge responds with invalid status code', () async {
    final harness = await _startProxyHarness((socket) async {
      final payload = _encodedResponsePayload(status: HttpStatus.ok);
      payload[2] = 0;
      payload[3] = 99;
      await _writeFramedPayload(socket, payload);
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, _) = await _requestText(harness.baseUri.replace(path: '/'));
    expect(status, HttpStatus.badGateway);
  });

  test('accepts chunked bridge response frames', () async {
    final harness = await _startProxyHarness((socket) async {
      await _writeFramedPayloads(
        socket,
        _encodedChunkedResponsePayloads(
          status: HttpStatus.ok,
          bodyBytes: utf8.encode('chunked response'),
        ),
      );
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, body) = await _requestText(
      harness.baseUri.replace(path: '/'),
    );
    expect(status, HttpStatus.ok);
    expect(body, 'chunked response');
  });

  test('returns 502 when chunked bridge response misses end frame', () async {
    final harness = await _startProxyHarness((socket) async {
      final startPayload = BridgeResponseFrame(
        status: HttpStatus.ok,
        headers: const <MapEntry<String, String>>[],
        bodyBytes: Uint8List(0),
      ).encodeStartPayload();
      await _writeFramedPayload(socket, startPayload);
      socket.destroy();
    });
    addTearDown(() async => harness.close());

    final (status, body) = await _requestText(
      harness.baseUri.replace(path: '/'),
    );
    expect(status, HttpStatus.badGateway);
    expect(body, contains('bridge call failed'));
    expect(
      body.contains('before response end') ||
          body.contains('read frame header failed'),
      isTrue,
    );
  });
}
