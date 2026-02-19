import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:server_native/src/bridge/bridge_runtime.dart';
import 'package:test/test.dart';

List<String> _headerValues(BridgeResponseFrame response, String name) {
  final target = name.toLowerCase();
  return response.headers
      .where((entry) => entry.key.toLowerCase() == target)
      .map((entry) => entry.value)
      .toList(growable: false);
}

BridgeRequestFrame _requestFrame({
  String method = 'GET',
  String scheme = 'http',
  String authority = '127.0.0.1',
  String path = '/',
  String query = '',
  String protocol = '1.1',
  List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
  List<int> bodyBytes = const <int>[],
}) {
  return BridgeRequestFrame(
    method: method,
    scheme: scheme,
    authority: authority,
    path: path,
    query: query,
    protocol: protocol,
    headers: headers,
    bodyBytes: Uint8List.fromList(bodyBytes),
  );
}

final class _LegacyFrameWriter {
  _LegacyFrameWriter() : _builder = BytesBuilder(copy: false);

  final BytesBuilder _builder;

  void writeUint8(int value) {
    _builder.add(<int>[value & 0xff]);
  }

  void writeUint16(int value) {
    _builder.add(<int>[(value >> 8) & 0xff, value & 0xff]);
  }

  void writeUint32(int value) {
    _builder.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void writeString(String value) {
    final bytes = utf8.encode(value);
    writeUint32(bytes.length);
    _builder.add(bytes);
  }

  void writeBytes(List<int> bytes) {
    writeUint32(bytes.length);
    _builder.add(bytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

Uint8List _legacyRequestPayload({
  required String method,
  required String scheme,
  required String authority,
  required String path,
  required String query,
  required String protocol,
  required List<MapEntry<String, String>> headers,
  required List<int> bodyBytes,
}) {
  final writer = _LegacyFrameWriter();
  writer.writeUint8(1);
  writer.writeUint8(1);
  writer.writeString(method);
  writer.writeString(scheme);
  writer.writeString(authority);
  writer.writeString(path);
  writer.writeString(query);
  writer.writeString(protocol);
  writer.writeUint32(headers.length);
  for (final header in headers) {
    writer.writeString(header.key);
    writer.writeString(header.value);
  }
  writer.writeBytes(bodyBytes);
  return writer.takeBytes();
}

Uint8List _legacyResponsePayload({
  required int status,
  required List<MapEntry<String, String>> headers,
  required List<int> bodyBytes,
}) {
  final writer = _LegacyFrameWriter();
  writer.writeUint8(1);
  writer.writeUint8(2);
  writer.writeUint16(status);
  writer.writeUint32(headers.length);
  for (final header in headers) {
    writer.writeString(header.key);
    writer.writeString(header.value);
  }
  writer.writeBytes(bodyBytes);
  return writer.takeBytes();
}

void main() {
  group('Bridge frame codec', () {
    test('applies defaults when request fields are empty', () {
      final payload = _requestFrame(
        method: '',
        scheme: '',
        authority: '',
        path: '',
        query: '',
        protocol: '',
      ).encodePayload();

      final decoded = BridgeRequestFrame.decodePayload(payload);
      expect(decoded.method, 'GET');
      expect(decoded.scheme, 'http');
      expect(decoded.authority, '127.0.0.1');
      expect(decoded.path, '/');
      expect(decoded.query, isEmpty);
      expect(decoded.protocol, '1.1');
      expect(decoded.headers, isEmpty);
      expect(decoded.bodyBytes, isEmpty);
    });

    test('round-trips request fields and body bytes', () {
      final payload = _requestFrame(
        method: 'post',
        scheme: 'https',
        authority: 'api.example.com',
        path: '/upload',
        query: 'a=1',
        protocol: '2',
        headers: const <MapEntry<String, String>>[
          MapEntry('x-one', '1'),
          MapEntry('x-two', '2'),
        ],
        bodyBytes: const <int>[1, 2, 3],
      ).encodePayload();

      final decoded = BridgeRequestFrame.decodePayload(payload);
      expect(decoded.method, 'POST');
      expect(decoded.scheme, 'https');
      expect(decoded.authority, 'api.example.com');
      expect(decoded.path, '/upload');
      expect(decoded.query, 'a=1');
      expect(decoded.protocol, '2');
      expect(decoded.headers.length, 2);
      expect(decoded.headers.first.key, 'x-one');
      expect(decoded.bodyBytes, Uint8List.fromList(const <int>[1, 2, 3]));
    });

    test('decodes legacy v1 request payloads', () {
      final payload = _legacyRequestPayload(
        method: 'post',
        scheme: 'https',
        authority: 'legacy.example',
        path: '/legacy',
        query: 'q=1',
        protocol: '1.1',
        headers: const <MapEntry<String, String>>[
          MapEntry('content-type', 'text/plain'),
        ],
        bodyBytes: utf8.encode('legacy body'),
      );

      final decoded = BridgeRequestFrame.decodePayload(payload);
      expect(decoded.method, 'POST');
      expect(decoded.scheme, 'https');
      expect(decoded.authority, 'legacy.example');
      expect(decoded.path, '/legacy');
      expect(decoded.query, 'q=1');
      expect(decoded.headers, hasLength(1));
      expect(decoded.headers.first.key, 'content-type');
      expect(utf8.decode(decoded.bodyBytes), 'legacy body');
    });

    test('throws FormatException for invalid request frame type', () {
      final payload = _requestFrame().encodePayload();
      payload[1] = 255;

      expect(
        () => BridgeRequestFrame.decodePayload(payload),
        throwsFormatException,
      );
    });

    test('round-trips response fields and body bytes', () {
      final payload = BridgeResponseFrame(
        status: HttpStatus.created,
        headers: const <MapEntry<String, String>>[
          MapEntry('content-type', 'application/json'),
          MapEntry('x-test', 'ok'),
        ],
        bodyBytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
      ).encodePayload();

      final decoded = BridgeResponseFrame.decodePayload(payload);
      expect(decoded.status, HttpStatus.created);
      expect(decoded.headers.length, 2);
      expect(decoded.headers.first.key, 'content-type');
      expect(utf8.decode(decoded.bodyBytes), '{"ok":true}');
    });

    test('decodes legacy v1 response payloads', () {
      final payload = _legacyResponsePayload(
        status: HttpStatus.accepted,
        headers: const <MapEntry<String, String>>[
          MapEntry('content-type', 'application/json'),
        ],
        bodyBytes: utf8.encode('{"legacy":true}'),
      );

      final decoded = BridgeResponseFrame.decodePayload(payload);
      expect(decoded.status, HttpStatus.accepted);
      expect(decoded.headers, hasLength(1));
      expect(decoded.headers.first.key, 'content-type');
      expect(utf8.decode(decoded.bodyBytes), '{"legacy":true}');
    });

    test('uses tokenized request frame type under protocol v1', () {
      const headers = <MapEntry<String, String>>[
        MapEntry('content-type', 'text/plain'),
      ];
      final payload = _requestFrame(headers: headers).encodePayload();
      expect(payload[0], 1);
      expect(payload[1], 11);
    });

    test('uses tokenized response frame type under protocol v1', () {
      const headers = <MapEntry<String, String>>[
        MapEntry('content-type', 'text/plain'),
      ];
      final payload = BridgeResponseFrame(
        status: HttpStatus.ok,
        headers: headers,
        bodyBytes: Uint8List(0),
      ).encodePayload();
      expect(payload[0], 1);
      expect(payload[1], 12);
    });

    test('round-trips chunked request frames', () {
      final startPayload = _requestFrame(
        method: 'put',
        scheme: 'https',
        authority: 'api.example.com',
        path: '/items',
        query: 'id=1',
        protocol: '2',
        headers: const <MapEntry<String, String>>[MapEntry('x-test', '1')],
      ).encodeStartPayload();
      final chunkPayload = BridgeRequestFrame.encodeChunkPayload(const <int>[
        1,
        2,
        3,
        4,
      ]);
      final endPayload = BridgeRequestFrame.encodeEndPayload();

      final start = BridgeRequestFrame.decodeStartPayload(startPayload);
      final chunk = BridgeRequestFrame.decodeChunkPayload(chunkPayload);
      BridgeRequestFrame.decodeEndPayload(endPayload);

      expect(start.method, 'PUT');
      expect(start.scheme, 'https');
      expect(start.authority, 'api.example.com');
      expect(start.path, '/items');
      expect(start.query, 'id=1');
      expect(start.protocol, '2');
      expect(start.headers, hasLength(1));
      expect(start.bodyBytes, isEmpty);
      expect(chunk, Uint8List.fromList(const <int>[1, 2, 3, 4]));
      expect(BridgeRequestFrame.isChunkPayload(chunkPayload), isTrue);
      expect(BridgeRequestFrame.isEndPayload(endPayload), isTrue);
    });

    test('round-trips chunked response frames', () {
      final startPayload = BridgeResponseFrame(
        status: HttpStatus.accepted,
        headers: const <MapEntry<String, String>>[
          MapEntry(HttpHeaders.contentTypeHeader, 'text/plain'),
        ],
        bodyBytes: Uint8List(0),
      ).encodeStartPayload();
      final chunkPayload = BridgeResponseFrame.encodeChunkPayload(
        utf8.encode('hello chunked'),
      );
      final endPayload = BridgeResponseFrame.encodeEndPayload();

      final start = BridgeResponseFrame.decodeStartPayload(startPayload);
      final chunk = BridgeResponseFrame.decodeChunkPayload(chunkPayload);
      BridgeResponseFrame.decodeEndPayload(endPayload);

      expect(start.status, HttpStatus.accepted);
      expect(start.headers, hasLength(1));
      expect(start.bodyBytes, isEmpty);
      expect(utf8.decode(chunk), 'hello chunked');
      expect(BridgeResponseFrame.isChunkPayload(chunkPayload), isTrue);
      expect(BridgeResponseFrame.isEndPayload(endPayload), isTrue);
    });

    test('round-trips tunnel chunk and close frames', () {
      final chunkPayload = BridgeTunnelFrame.encodeChunkPayload(const <int>[
        9,
        8,
        7,
      ]);
      final closePayload = BridgeTunnelFrame.encodeClosePayload();

      final decodedChunk = BridgeTunnelFrame.decodeChunkPayload(chunkPayload);
      BridgeTunnelFrame.decodeClosePayload(closePayload);

      expect(decodedChunk, Uint8List.fromList(const <int>[9, 8, 7]));
      expect(BridgeTunnelFrame.isChunkPayload(chunkPayload), isTrue);
      expect(BridgeTunnelFrame.isClosePayload(closePayload), isTrue);
    });
  });

  group('BridgeHttpRuntime', () {
    test('handles request with plain HttpRequest-style callback', () async {
      final runtime = BridgeHttpRuntime((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.created;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/plain',
        );
        request.response.headers.set('x-path', request.uri.path);
        request.response.write('echo:$requestBody');
        await request.response.close();
      });

      final response = await runtime.handleFrame(
        _requestFrame(
          method: 'POST',
          path: '/raw',
          headers: const <MapEntry<String, String>>[
            MapEntry(HttpHeaders.contentTypeHeader, 'text/plain'),
          ],
          bodyBytes: utf8.encode('hello bridge'),
        ),
      );

      expect(response.status, HttpStatus.created);
      expect(
        _headerValues(response, HttpHeaders.contentTypeHeader),
        contains('text/plain'),
      );
      expect(_headerValues(response, 'x-path'), contains('/raw'));
      expect(utf8.decode(response.bodyBytes), 'echo:hello bridge');
    });
  });

  group('BridgeRuntime', () {
    test('handles method/query/header/body roundtrip', () async {
      final engine = Engine()
        ..post('/echo', (ctx) async {
          return ctx.json({
            'method': ctx.method,
            'query': ctx.query('q'),
            'header': ctx.requestHeader('x-test'),
            'body': await ctx.body(),
          });
        });
      final runtime = BridgeHttpRuntime(engine.handleRequest);

      final response = await runtime.handleFrame(
        _requestFrame(
          method: 'POST',
          scheme: 'http',
          authority: 'localhost',
          path: '/echo',
          query: 'q=1',
          protocol: '1.1',
          headers: const <MapEntry<String, String>>[
            MapEntry('x-test', 'bridge'),
            MapEntry(HttpHeaders.contentTypeHeader, 'text/plain'),
          ],
          bodyBytes: utf8.encode('hello runtime'),
        ),
      );

      expect(response.status, HttpStatus.ok);
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      expect(json, {
        'method': 'POST',
        'query': '1',
        'header': 'bridge',
        'body': 'hello runtime',
      });
    });

    test('preserves set-cookie headers from response', () async {
      final engine = Engine()
        ..get('/cookies', (ctx) async {
          ctx.response.setCookie('session', 'abc');
          await ctx.response.string('ok');
          return ctx.response;
        });
      final runtime = BridgeHttpRuntime(engine.handleRequest);

      final response = await runtime.handleFrame(
        _requestFrame(method: 'GET', path: '/cookies'),
      );

      expect(response.status, HttpStatus.ok);
      final setCookies = _headerValues(response, HttpHeaders.setCookieHeader);
      expect(setCookies, isNotEmpty);
      expect(
        setCookies.any((value) => value.startsWith('session=abc')),
        isTrue,
      );
    });

    test('preserves not-found behavior', () async {
      final runtime = BridgeHttpRuntime(Engine().handleRequest);
      final response = await runtime.handleFrame(
        _requestFrame(method: 'GET', path: '/missing'),
      );

      expect(response.status, HttpStatus.notFound);
      expect(utf8.decode(response.bodyBytes), contains('Not Found'));
    });

    test('preserves redirect status and location', () async {
      final engine = Engine()
        ..get('/redirect', (ctx) async {
          ctx.response.redirect('/target', status: HttpStatus.found);
          return ctx.response;
        });
      final runtime = BridgeHttpRuntime(engine.handleRequest);

      final response = await runtime.handleFrame(
        _requestFrame(method: 'GET', path: '/redirect'),
      );

      expect(response.status, HttpStatus.found);
      final location = _headerValues(response, HttpHeaders.locationHeader);
      expect(location, isNotEmpty);
      expect(location.first, '/target');
    });

    test('returns 500 response when handler throws', () async {
      final engine = Engine()
        ..get('/boom', (ctx) {
          throw StateError('boom');
        });
      final runtime = BridgeHttpRuntime(engine.handleRequest);

      final response = await runtime.handleFrame(
        _requestFrame(method: 'GET', path: '/boom'),
      );

      expect(response.status, HttpStatus.internalServerError);
      expect(utf8.decode(response.bodyBytes), isNotEmpty);
    });

    test(
      'streams request body and response chunks with handleStream',
      () async {
        final engine = Engine()
          ..post('/stream', (ctx) async {
            final body = await ctx.body();
            ctx.response.statusCode = HttpStatus.accepted;
            ctx.response.headers.set('x-body-len', body.length.toString());
            ctx.response.write('prefix:');
            ctx.response.write(body);
            ctx.response.write(':suffix');
            await ctx.response.close();
            return ctx.response;
          });
        final runtime = BridgeHttpRuntime(engine.handleRequest);

        final startFrames = <BridgeResponseFrame>[];
        final responseChunks = <Uint8List>[];
        final requestBody = StreamController<Uint8List>();

        final future = runtime.handleStream(
          frame: _requestFrame(method: 'POST', path: '/stream'),
          bodyStream: requestBody.stream,
          onResponseStart: (frame) async {
            startFrames.add(frame);
          },
          onResponseChunk: (chunkBytes) async {
            responseChunks.add(Uint8List.fromList(chunkBytes));
          },
        );

        requestBody.add(Uint8List.fromList(utf8.encode('hello ')));
        requestBody.add(Uint8List.fromList(utf8.encode('stream')));
        await requestBody.close();
        await future;

        expect(startFrames, hasLength(1));
        expect(startFrames.single.status, HttpStatus.accepted);
        final bodyLengthHeaders = _headerValues(
          startFrames.single,
          'x-body-len',
        );
        expect(bodyLengthHeaders, isNotEmpty);
        expect(bodyLengthHeaders.first, '12');
        expect(
          utf8.decode(responseChunks.expand((chunk) => chunk).toList()),
          'prefix:hello stream:suffix',
        );
      },
    );
  });
}
