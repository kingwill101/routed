import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart' as http2;
import 'package:http2/transport.dart'
    show HeadersStreamMessage, DataStreamMessage;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  group('HTTP/2 server', () {
    late Engine engine;
    late SecurityContext clientContext;

    setUp(() async {
      engine = testEngine(
        config: EngineConfig(http2: const Http2Config(enabled: true)),
      );

      engine.get('/', (ctx) => ctx.string('hello http2'));
      engine.get('/json', (ctx) => ctx.json({'status': 'ok'}));

      final certPath = _locateHttp2Asset('cert.pem');
      final keyPath = _locateHttp2Asset('key.pem');

      clientContext = SecurityContext()..setTrustedCertificates(certPath);

      // Start server in background.
      unawaited(
        engine.serveSecure(
          address: '127.0.0.1',
          port: 0,
          certificatePath: certPath,
          keyPath: keyPath,
        ),
      );

      await _waitForServer(engine);
    });

    tearDown(() async {
      await engine.close();
    });

    test('responds to HTTP/2 GET requests', () async {
      final response = await _makeHttp2Request(
        engine.httpPort!,
        clientContext,
        path: '/',
      );

      expect(response.status, equals('200'));
      expect(response.body, equals('hello http2'));
    });

    test('returns JSON payload under HTTP/2', () async {
      final response = await _makeHttp2Request(
        engine.httpPort!,
        clientContext,
        path: '/json',
      );

      expect(response.status, equals('200'));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      expect(decoded['status'], equals('ok'));
    });
  });
}

String _locateHttp2Asset(String filename) {
  final candidates = [
    p.join('examples', 'http2', filename),
    p.join('..', 'examples', 'http2', filename),
    p.join('..', '..', 'examples', 'http2', filename),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'Unable to locate $filename. Searched in: ${candidates.join(', ')}',
  );
}

Future<void> _waitForServer(Engine engine) async {
  for (var i = 0; i < 50; i++) {
    if (engine.httpPort != null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Engine did not start listening in time');
}

class _Http2Response {
  _Http2Response({
    required this.status,
    required this.headers,
    required this.body,
  });

  final String status;
  final Map<String, String> headers;
  final String body;
}

Future<_Http2Response> _makeHttp2Request(
  int port,
  SecurityContext clientContext, {
  required String path,
}) async {
  final socket = await SecureSocket.connect(
    'localhost',
    port,
    supportedProtocols: const ['h2'],
    context: clientContext,
    onBadCertificate: (_) => true,
  );

  final connection = http2.ClientTransportConnection.viaSocket(socket);
  try {
    final requestHeaders = [
      http2.Header.ascii(':method', 'GET'),
      http2.Header.ascii(':scheme', 'https'),
      http2.Header.ascii(':path', path),
      http2.Header.ascii(':authority', 'localhost:$port'),
    ];

    final stream = connection.makeRequest(requestHeaders, endStream: true);

    HeadersStreamMessage? headerFrame;
    final buffer = BytesBuilder();
    await for (final message in stream.incomingMessages) {
      if (message is HeadersStreamMessage) {
        headerFrame = message;
      } else if (message is DataStreamMessage) {
        buffer.add(message.bytes);
      }
    }

    if (headerFrame == null) {
      throw StateError('No response headers received');
    }

    final headers = <String, String>{};
    String status = '500';
    for (final header in headerFrame.headers) {
      final name = ascii.decode(header.name);
      final value = utf8.decode(header.value);
      if (name == ':status') {
        status = value;
      } else {
        headers[name] = value;
      }
    }

    return _Http2Response(
      status: status,
      headers: headers,
      body: utf8.decode(buffer.takeBytes()),
    );
  } finally {
    await connection.finish();
    await socket.close();
  }
}
