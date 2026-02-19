import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

final class _RunningFfiServer {
  _RunningFfiServer({
    required this.baseUri,
    required this.shutdown,
    required this.serveFuture,
  });

  final Uri baseUri;
  final Completer<void> shutdown;
  final Future<void> serveFuture;
}

final class _RunningNativeMultiServer {
  _RunningNativeMultiServer({
    required this.baseUris,
    required this.shutdown,
    required this.serveFuture,
  });

  final List<Uri> baseUris;
  final Completer<void> shutdown;
  final Future<void> serveFuture;
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _supportsLoopbackIPv4() async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

Future<bool> _supportsLoopbackIPv6() async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

Future<_RunningFfiServer> _startServer(
  Engine engine, {
  bool nativeCallback = false,
}) async {
  final shutdown = Completer<void>();
  final port = await _reservePort();
  final serveFuture = serveNative(
    engine,
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    echo: false,
    http3: false,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdown.future,
  );

  final baseUri = Uri.parse('http://127.0.0.1:$port');
  await _waitUntilUp(baseUri.replace(path: '/'));

  return _RunningFfiServer(
    baseUri: baseUri,
    shutdown: shutdown,
    serveFuture: serveFuture,
  );
}

Future<_RunningNativeMultiServer> _startMultiServer(
  Engine engine, {
  bool nativeCallback = false,
  int listeners = 2,
}) async {
  final shutdown = Completer<void>();
  final ports = <int>[];
  for (var i = 0; i < listeners; i++) {
    ports.add(await _reservePort());
  }
  final binds = ports
      .map(
        (port) => NativeServerBind(
          host: InternetAddress.loopbackIPv4.address,
          port: port,
        ),
      )
      .toList(growable: false);
  final serveFuture = serveNativeMulti(
    engine,
    binds: binds,
    echo: false,
    http3: false,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdown.future,
  );

  final baseUris = ports
      .map((port) => Uri.parse('http://127.0.0.1:$port'))
      .toList(growable: false);
  for (final baseUri in baseUris) {
    await _waitUntilUp(baseUri.replace(path: '/'));
  }

  return _RunningNativeMultiServer(
    baseUris: baseUris,
    shutdown: shutdown,
    serveFuture: serveFuture,
  );
}

Future<_RunningFfiServer> _startSecureServer(
  Engine engine, {
  required String certificatePath,
  required String keyPath,
  String? certificatePassword,
  bool requestClientCertificate = false,
  bool http3 = false,
}) async {
  final shutdown = Completer<void>();
  final port = await _reservePort();
  final serveFuture = serveSecureNative(
    engine,
    address: InternetAddress.loopbackIPv4.address,
    port: port,
    certificatePath: certificatePath,
    keyPath: keyPath,
    certificatePassword: certificatePassword,
    requestClientCertificate: requestClientCertificate,
    http3: http3,
    shutdownSignal: shutdown.future,
  );

  final baseUri = Uri.parse('https://127.0.0.1:$port');
  await _waitUntilUp(baseUri.replace(path: '/'), allowBadCertificate: true);

  return _RunningFfiServer(
    baseUri: baseUri,
    shutdown: shutdown,
    serveFuture: serveFuture,
  );
}

Future<void> _stopServer(_RunningFfiServer running, Engine engine) async {
  if (!running.shutdown.isCompleted) {
    running.shutdown.complete();
  }
  await engine.close();
  await running.serveFuture.timeout(const Duration(seconds: 5));
}

Future<void> _stopMultiServer(
  _RunningNativeMultiServer running,
  Engine engine,
) async {
  if (!running.shutdown.isCompleted) {
    running.shutdown.complete();
  }
  await engine.close();
  await running.serveFuture.timeout(const Duration(seconds: 5));
}

Future<void> _waitUntilUp(Uri uri, {bool allowBadCertificate = false}) async {
  final client = HttpClient();
  if (allowBadCertificate) {
    client.badCertificateCallback = (_, _, _) => true;
  }
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

Future<bool> _curlSupportsHttp3() async {
  try {
    final result = await Process.run('curl', const ['--version']);
    if (result.exitCode != 0) {
      return false;
    }
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('http3');
  } on ProcessException {
    return false;
  }
}

Future<ProcessResult> _curlHttp3GetWithRetry(
  Uri uri, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  ProcessResult? lastResult;

  while (true) {
    lastResult = await Process.run('curl', [
      '--http3-only',
      '--silent',
      '--show-error',
      '--insecure',
      '--output',
      '-',
      '--write-out',
      r'\n%{http_version}',
      uri.toString(),
    ]);

    if (lastResult.exitCode == 0) {
      return lastResult;
    }

    final stderrText = lastResult.stderr.toString().toLowerCase();
    final retryableError =
        stderrText.contains('connection refused') ||
        stderrText.contains('could not connect') ||
        stderrText.contains('failed to connect') ||
        stderrText.contains('timed out');
    if (!retryableError || DateTime.now().isAfter(deadline)) {
      return lastResult;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

String _locateTlsAsset(String filename) {
  final candidates = <String>[
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

void main() {
  test('serveNative proxies GET requests to routed engine handlers', () async {
    final engine = Engine()
      ..get('/ping', (ctx) async => ctx.json({'ok': true}));

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/ping');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), {'ok': true});
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test(
    'serveNative native callback mode proxies GET requests to routed engine handlers',
    () async {
      final engine = Engine()
        ..get('/ping', (ctx) async => ctx.json({'ok': true}));

      final running = await _startServer(engine, nativeCallback: true);
      final uri = running.baseUri.replace(path: '/ping');

      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(body), {'ok': true});
      } finally {
        client.close(force: true);
      }

      await _stopServer(running, engine);
    },
  );

  test('serveNativeMulti proxies GET requests on each bind', () async {
    final engine = Engine()
      ..get('/ping', (ctx) async => ctx.json({'ok': true}));

    final running = await _startMultiServer(engine);
    final client = HttpClient();
    try {
      for (final baseUri in running.baseUris) {
        final req = await client.getUrl(baseUri.replace(path: '/ping'));
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(body), {'ok': true});
      }
    } finally {
      client.close(force: true);
    }

    await _stopMultiServer(running, engine);
  });

  test(
    'serveNativeMulti native callback mode proxies GET requests on each bind',
    () async {
      final engine = Engine()
        ..get('/ping', (ctx) async => ctx.json({'ok': true}));

      final running = await _startMultiServer(engine, nativeCallback: true);
      final client = HttpClient();
      try {
        for (final baseUri in running.baseUris) {
          final req = await client.getUrl(baseUri.replace(path: '/ping'));
          final res = await req.close();
          final body = await utf8.decodeStream(res);

          expect(res.statusCode, HttpStatus.ok);
          expect(jsonDecode(body), {'ok': true});
        }
      } finally {
        client.close(force: true);
      }

      await _stopMultiServer(running, engine);
    },
  );

  test('serveNativeMulti throws when binds list is empty', () async {
    final engine = Engine();
    await expectLater(
      () => serveNativeMulti(engine, binds: const <NativeServerBind>[]),
      throwsArgumentError,
    );
    await engine.close();
  });

  test('NativeMultiServer.bind handles localhost like loopback', () async {
    final engine = Engine()
      ..get('/ping', (ctx) async => ctx.json({'ok': true}));

    final shutdown = Completer<void>();
    final port = await _reservePort();
    final serveFuture = NativeMultiServer.bind(
      engine,
      'localhost',
      port,
      echo: false,
      http3: false,
      shutdownSignal: shutdown.future,
    );

    final client = HttpClient();
    try {
      final v4Supported = await _supportsLoopbackIPv4();
      final v6Supported = await _supportsLoopbackIPv6();
      if (v4Supported) {
        final uri = Uri.parse('http://127.0.0.1:$port/ping');
        await _waitUntilUp(uri);
        final req = await client.getUrl(uri);
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(await utf8.decodeStream(res)), {'ok': true});
      }
      if (v6Supported) {
        final uri = Uri.parse('http://[::1]:$port/ping');
        await _waitUntilUp(uri);
        final req = await client.getUrl(uri);
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(await utf8.decodeStream(res)), {'ok': true});
      }
      expect(v4Supported || v6Supported, isTrue);
    } finally {
      client.close(force: true);
    }

    shutdown.complete();
    await engine.close();
    await serveFuture.timeout(const Duration(seconds: 5));
  });

  test('NativeMultiServer.bind handles any', () async {
    final engine = Engine()
      ..get('/ping', (ctx) async => ctx.json({'ok': true}));

    final shutdown = Completer<void>();
    final port = await _reservePort();
    final serveFuture = NativeMultiServer.bind(
      engine,
      'any',
      port,
      echo: false,
      http3: false,
      shutdownSignal: shutdown.future,
    );

    final uri = Uri.parse('http://127.0.0.1:$port/ping');
    await _waitUntilUp(uri);

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(await utf8.decodeStream(res)), {'ok': true});
    } finally {
      client.close(force: true);
    }

    shutdown.complete();
    await engine.close();
    await serveFuture.timeout(const Duration(seconds: 5));
  });

  test('serveNative forwards method, headers, query, and body', () async {
    final engine = Engine()
      ..post('/echo', (ctx) async {
        final body = await ctx.body();
        return ctx.json({
          'method': ctx.method,
          'query': ctx.query('q'),
          'header': ctx.requestHeader('x-test'),
          'body': body,
        });
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(
      path: '/echo',
      queryParameters: {'q': '1'},
    );

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('x-test', 'bridge');
      req.headers.contentType = ContentType.text;
      req.write('hello bridge');
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), {
        'method': 'POST',
        'query': '1',
        'header': 'bridge',
        'body': 'hello bridge',
      });
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative preserves response cookies', () async {
    final engine = Engine()
      ..get('/cookies', (ctx) async {
        ctx.response.setCookie('session', 'abc');
        ctx.response.setCookie('theme', 'dark');
        await ctx.response.string('ok');
        return ctx.response;
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/cookies');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      await res.drain<void>();

      final setCookieValues = res.headers[HttpHeaders.setCookieHeader] ?? [];
      expect(setCookieValues, isNotEmpty);
      expect(
        setCookieValues.any((value) => value.startsWith('session=abc')),
        isTrue,
      );
      expect(
        setCookieValues.any((value) => value.startsWith('theme=dark')),
        isTrue,
      );
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative forwards websocket upgrade and messages', () async {
    final engine = Engine()..ws('/ws', _EchoWebSocketHandler());

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(scheme: 'ws', path: '/ws');

    final socket = await WebSocket.connect(uri.toString());
    try {
      socket.add('ping');
      final firstMessage = await socket.first.timeout(
        const Duration(seconds: 3),
      );
      expect(firstMessage, 'echo:ping');
      await socket.close();
    } finally {
      await socket.close();
    }

    await _stopServer(running, engine);
  });

  test('serveNative preserves non-200 status codes', () async {
    final engine = Engine()
      ..get('/created', (ctx) async {
        await ctx.response.json({'ok': true}, statusCode: HttpStatus.created);
        return ctx.response;
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/created');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      expect(res.statusCode, HttpStatus.created);
      expect(jsonDecode(body), {'ok': true});
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative handles binary request bodies', () async {
    final engine = Engine()
      ..post('/bytes', (ctx) async {
        final bytes = await ctx.bodyBytes;
        return ctx.json({
          'length': bytes.length,
          'first': bytes.isEmpty ? -1 : bytes.first,
          'last': bytes.isEmpty ? -1 : bytes.last,
        });
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/bytes');

    final payload = <int>[0, 1, 2, 3, 254, 255];
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.add(payload);
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), {'length': 6, 'first': 0, 'last': 255});
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative handles repeated response headers', () async {
    final engine = Engine()
      ..get('/headers', (ctx) async {
        ctx.response.addHeader('x-multi', 'a');
        ctx.response.addHeader('x-multi', 'b');
        await ctx.response.string('ok');
        return ctx.response;
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/headers');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      await res.drain<void>();

      final values = res.headers['x-multi'] ?? const <String>[];
      expect(values, isNotEmpty);
      expect(values.first, contains('a'));
      expect(values.first, contains('b'));
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative preserves 404 behavior', () async {
    final engine = Engine();
    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/missing');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative handles concurrent requests', () async {
    final engine = Engine()
      ..get('/slow', (ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return ctx.json({'ok': true});
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/slow');
    final client = HttpClient();

    try {
      final futures = List<Future<HttpClientResponse>>.generate(10, (_) async {
        final req = await client.getUrl(uri);
        return req.close();
      });
      final responses = await Future.wait(futures);
      for (final response in responses) {
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();
      }
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative preserves redirect status and location headers', () async {
    final engine = Engine()
      ..get('/redirect', (ctx) async {
        ctx.response.redirect('/target', status: HttpStatus.found);
        return ctx.response;
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/redirect');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      final res = await req.close();
      expect(res.statusCode, HttpStatus.found);
      expect(res.headers.value(HttpHeaders.locationHeader), '/target');
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative forwards repeated request header values', () async {
    final engine = Engine()
      ..get('/header-echo', (ctx) async {
        return ctx.json({'value': ctx.requestHeader('x-multi') ?? ''});
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/header-echo');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.add('x-multi', 'a');
      req.headers.add('x-multi', 'b');
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      final value =
          (jsonDecode(body) as Map<String, dynamic>)['value'] as String;
      expect(res.statusCode, HttpStatus.ok);
      expect(value, contains('a'));
      expect(value, contains('b'));
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative handles large request payloads', () async {
    final engine = Engine()
      ..post('/size', (ctx) async {
        final bytes = await ctx.bodyBytes;
        return ctx.json({'length': bytes.length});
      });

    final running = await _startServer(engine);
    final uri = running.baseUri.replace(path: '/size');
    final payload = List<int>.generate(512 * 1024, (index) => index % 256);

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.add(payload);
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), {'length': payload.length});
    } finally {
      client.close(force: true);
    }

    await _stopServer(running, engine);
  });

  test('serveNative completes when shutdown signal is triggered', () async {
    final engine = Engine()..get('/', (ctx) async => ctx.string('ok'));
    final running = await _startServer(engine);

    running.shutdown.complete();
    await running.serveFuture.timeout(const Duration(seconds: 5));
    await engine.close();
  });

  test(
    'serveSecureNative proxies HTTPS requests via native TLS transport',
    () async {
      final certPath = _locateTlsAsset('cert.pem');
      final keyPath = _locateTlsAsset('key.pem');
      final engine = Engine()
        ..get('/secure', (ctx) async => ctx.json({'secure': true}));

      final running = await _startSecureServer(
        engine,
        certificatePath: certPath,
        keyPath: keyPath,
      );
      final uri = running.baseUri.replace(path: '/secure');

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(body), {'secure': true});
      } finally {
        client.close(force: true);
      }

      await _stopServer(running, engine);
    },
  );

  test('serveSecureNative serves HTTP/3 requests when enabled', () async {
    if (!await _curlSupportsHttp3()) {
      markTestSkipped('curl with HTTP/3 support is unavailable');
      return;
    }

    final certPath = _locateTlsAsset('cert.pem');
    final keyPath = _locateTlsAsset('key.pem');
    final engine = Engine()..get('/h3', (ctx) async => ctx.string('h3-ok'));

    final running = await _startSecureServer(
      engine,
      certificatePath: certPath,
      keyPath: keyPath,
      http3: true,
    );
    final uri = running.baseUri.replace(path: '/h3');

    try {
      final result = await _curlHttp3GetWithRetry(uri);

      expect(
        result.exitCode,
        0,
        reason: 'curl failed: stdout=${result.stdout} stderr=${result.stderr}',
      );

      final stdoutText = result.stdout as String;
      final lines = const LineSplitter().convert(stdoutText.trimRight());
      expect(lines, isNotEmpty);
      final httpVersion = lines.last.trim();
      final body = lines.take(lines.length - 1).join('\n');

      expect(httpVersion, startsWith('3'));
      expect(body, 'h3-ok');
    } finally {
      await _stopServer(running, engine);
    }
  });

  test(
    'serveSecureNative accepts requestClientCertificate without requiring client cert',
    () async {
      final certPath = _locateTlsAsset('cert.pem');
      final keyPath = _locateTlsAsset('key.pem');
      final engine = Engine()
        ..get('/mtls-optional', (ctx) async => ctx.string('ok'));

      final running = await _startSecureServer(
        engine,
        certificatePath: certPath,
        keyPath: keyPath,
        requestClientCertificate: true,
      );
      final uri = running.baseUri.replace(path: '/mtls-optional');

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(await utf8.decodeStream(res), 'ok');
      } finally {
        client.close(force: true);
      }

      await _stopServer(running, engine);
    },
  );

  test(
    'serveSecureNative supports encrypted private keys with certificatePassword',
    () async {
      final certPath = _locateTlsAsset('cert.pem');
      final keyPath = _locateTlsAsset('key_encrypted.pem');
      final engine = Engine()
        ..get('/secure-password', (ctx) async => ctx.string('ok'));

      final running = await _startSecureServer(
        engine,
        certificatePath: certPath,
        keyPath: keyPath,
        certificatePassword: 'routed-test-pass',
      );
      final uri = running.baseUri.replace(path: '/secure-password');

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(await utf8.decodeStream(res), 'ok');
      } finally {
        client.close(force: true);
      }

      await _stopServer(running, engine);
    },
  );

  test('serveSecureNative fails with wrong certificatePassword', () async {
    final certPath = _locateTlsAsset('cert.pem');
    final keyPath = _locateTlsAsset('key_encrypted.pem');
    final engine = Engine();

    await expectLater(
      () => _startSecureServer(
        engine,
        certificatePath: certPath,
        keyPath: keyPath,
        certificatePassword: 'wrong-pass',
      ),
      throwsStateError,
    );
    await engine.close();
  });

  test('serveSecureNative throws when certificate paths are missing', () async {
    final engine = Engine();
    await expectLater(
      () => serveSecureNative(
        engine,
        address: '127.0.0.1',
        port: 0,
        certificatePath: null,
        keyPath: null,
      ),
      throwsArgumentError,
    );
    await engine.close();
  });

  test('serveSecureNativeMulti throws when binds list is empty', () async {
    final engine = Engine();
    await expectLater(
      () => serveSecureNativeMulti(
        engine,
        binds: const <NativeServerBind>[],
        certificatePath: 'cert.pem',
        keyPath: 'key.pem',
      ),
      throwsArgumentError,
    );
    await engine.close();
  });

  test(
    'serveSecureNativeMulti throws when certificate paths are missing',
    () async {
      final engine = Engine();
      await expectLater(
        () => serveSecureNativeMulti(
          engine,
          binds: const <NativeServerBind>[NativeServerBind()],
          certificatePath: '',
          keyPath: '',
        ),
        throwsArgumentError,
      );
      await engine.close();
    },
  );
}

final class _EchoWebSocketHandler extends WebSocketHandler {
  @override
  Future<void> onOpen(WebSocketContext context) async {}

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    context.send('echo:$message');
  }

  @override
  Future<void> onClose(WebSocketContext context) async {}

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {}
}
