import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

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

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Timed out waiting for predicate');
}

String? _sessionCookieFrom(HttpClientResponse response) {
  final setCookieValues = response.headers[HttpHeaders.setCookieHeader];
  if (setCookieValues == null) {
    return null;
  }
  for (final value in setCookieValues) {
    if (!value.startsWith('DARTSESSID=')) {
      continue;
    }
    final separator = value.indexOf(';');
    return separator == -1 ? value : value.substring(0, separator);
  }
  return null;
}

void main() {
  test(
    'NativeHttpServer.bind serves requests and applies default headers',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
      );
      addTearDown(() => server.close(force: true));

      server.serverHeader = 'routed-ffi-test';
      server.defaultResponseHeaders.set('x-default', '1');
      // ignore: discarded_futures
      server.listen((request) async {
        request.response.write('ok');
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(body, 'ok');
      expect(res.headers.value(HttpHeaders.serverHeader), 'routed-ffi-test');
      expect(res.headers.value('x-default'), '1');
    },
  );

  test(
    'NativeHttpServer.bind supports nativeCallback HttpRequest mode',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
        nativeCallback: true,
      );
      addTearDown(() => server.close(force: true));

      // ignore: discarded_futures
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('x-mode', 'native-callback')
          ..write('echo:$body');
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/echo'),
      );
      req.add(utf8.encode('hello'));
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.value('x-mode'), 'native-callback');
      expect(body, 'echo:hello');
    },
  );

  test(
    'NativeHttpServer.bind supports WebSocket upgrade with nativeCallback',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
        nativeCallback: true,
      );
      addTearDown(() => server.close(force: true));

      // ignore: discarded_futures
      server.listen((request) async {
        if (request.uri.path == '/ws') {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen(
            (message) => socket.add('echo:$message'),
            onDone: () => socket.close(),
            cancelOnError: false,
          );
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}/ws');
      final webSocket = await WebSocket.connect(wsUri.toString());
      try {
        webSocket.add('ping');
        final message = await webSocket.first.timeout(
          const Duration(seconds: 3),
        );
        expect(message, 'echo:ping');
        await webSocket.close();
      } finally {
        await webSocket.close();
      }
    },
  );

  test('NativeHttpServer.bind handles localhost loopback semantics', () async {
    final server = await NativeHttpServer.bind('localhost', 0, http3: false);
    addTearDown(() => server.close(force: true));

    // ignore: discarded_futures
    server.listen((request) async {
      request.response.write('ok');
      await request.response.close();
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final v4Supported = await _supportsLoopbackIPv4();
    final v6Supported = await _supportsLoopbackIPv6();
    if (v4Supported) {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      expect(await utf8.decodeStream(res), 'ok');
    }
    if (v6Supported) {
      final req = await client.getUrl(
        Uri.parse('http://[::1]:${server.port}/'),
      );
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      expect(await utf8.decodeStream(res), 'ok');
    }
    expect(v4Supported || v6Supported, isTrue);
  });

  test('NativeHttpServer.connectionsInfo tracks active requests', () async {
    final server = await NativeHttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      http3: false,
    );
    addTearDown(() => server.close(force: true));

    final gate = Completer<void>();
    // ignore: discarded_futures
    server.listen((request) async {
      await gate.future;
      request.response.write('ok');
      await request.response.close();
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final responseFuture = req.close();

    await _waitFor(() => server.connectionsInfo().active > 0);
    final inflight = server.connectionsInfo();
    expect(inflight.total, greaterThan(0));
    expect(inflight.active, greaterThan(0));

    gate.complete();
    final response = await responseFuture;
    await response.drain<void>();

    await _waitFor(() => server.connectionsInfo().active == 0);
  });

  test(
    'NativeHttpServer server header precedence matches HttpServer semantics',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
      );
      addTearDown(() => server.close(force: true));

      server.defaultResponseHeaders.set(
        HttpHeaders.serverHeader,
        'default-server',
      );
      // ignore: discarded_futures
      server.listen((request) async {
        request.response.write('ok');
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final firstReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/first'),
      );
      final firstRes = await firstReq.close();
      await firstRes.drain<void>();
      expect(
        firstRes.headers.value(HttpHeaders.serverHeader),
        'default-server',
      );

      server.serverHeader = 'override-server';
      final secondReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/second'),
      );
      final secondRes = await secondReq.close();
      await secondRes.drain<void>();
      expect(
        secondRes.headers.value(HttpHeaders.serverHeader),
        'override-server',
      );
    },
  );

  test(
    'NativeHttpServer defaultResponseHeaders clear removes defaults',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
      );
      addTearDown(() => server.close(force: true));

      // ignore: discarded_futures
      server.listen((request) async {
        request.response.write('ok');
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final firstReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/first'),
      );
      final firstRes = await firstReq.close();
      await firstRes.drain<void>();
      expect(firstRes.headers.value('x-frame-options'), 'SAMEORIGIN');

      server.defaultResponseHeaders.clear();
      final secondReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/second'),
      );
      final secondRes = await secondReq.close();
      await secondRes.drain<void>();
      expect(secondRes.headers.value('x-frame-options'), isNull);
    },
  );

  test(
    'NativeHttpServer reconstructs requestedUri from forwarded headers',
    () async {
      final server = await NativeHttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        http3: false,
      );
      addTearDown(() => server.close(force: true));

      // ignore: discarded_futures
      server.listen((request) async {
        request.response.write(request.requestedUri.toString());
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/forwarded?x=1'),
      );
      req.headers.set('x-forwarded-proto', 'https');
      req.headers.set('x-forwarded-host', 'example.test:8443');
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      expect(res.statusCode, HttpStatus.ok);
      expect(body, 'https://example.test:8443/forwarded?x=1');
    },
  );

  test('NativeHttpServer session persists, destroys, and renews', () async {
    final server = await NativeHttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      http3: false,
    );
    addTearDown(() => server.close(force: true));

    // ignore: discarded_futures
    server.listen((request) async {
      if (request.uri.path == '/destroy') {
        request.session.destroy();
        request.response.write('destroyed');
        await request.response.close();
        return;
      }
      final count = ((request.session['count'] as int?) ?? 0) + 1;
      request.session['count'] = count;
      request.response.write(
        '${request.session.id}|${request.session.isNew}|$count',
      );
      await request.response.close();
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final firstReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/session'),
    );
    final firstRes = await firstReq.close();
    final firstBody = await utf8.decodeStream(firstRes);
    final firstParts = firstBody.split('|');
    final cookieHeader = _sessionCookieFrom(firstRes);
    expect(firstParts[1], 'true');
    expect(firstParts[2], '1');
    expect(cookieHeader, isNotNull);

    final secondReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/session'),
    );
    secondReq.headers.set(HttpHeaders.cookieHeader, cookieHeader!);
    final secondRes = await secondReq.close();
    final secondBody = await utf8.decodeStream(secondRes);
    final secondParts = secondBody.split('|');
    expect(secondParts[0], firstParts[0]);
    expect(secondParts[1], 'false');
    expect(secondParts[2], '2');

    final destroyReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/destroy'),
    );
    destroyReq.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    final destroyRes = await destroyReq.close();
    await destroyRes.drain<void>();

    final thirdReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/session'),
    );
    final thirdRes = await thirdReq.close();
    final thirdBody = await utf8.decodeStream(thirdRes);
    final thirdParts = thirdBody.split('|');
    expect(thirdParts[0], isNot(firstParts[0]));
    expect(thirdParts[1], 'true');
    expect(thirdParts[2], '1');
  });

  test('NativeHttpServer sessionTimeout expires sessions', () async {
    final server = await NativeHttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      http3: false,
    );
    addTearDown(() => server.close(force: true));
    server.sessionTimeout = 1;

    // ignore: discarded_futures
    server.listen((request) async {
      request.response.write('${request.session.id}|${request.session.isNew}');
      await request.response.close();
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final firstReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/session-timeout'),
    );
    final firstRes = await firstReq.close();
    final firstBody = await utf8.decodeStream(firstRes);
    final firstParts = firstBody.split('|');
    final cookieHeader = _sessionCookieFrom(firstRes);
    expect(firstParts[1], 'true');
    expect(cookieHeader, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 1400));

    final secondReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/session-timeout'),
    );
    secondReq.headers.set(HttpHeaders.cookieHeader, cookieHeader!);
    final secondRes = await secondReq.close();
    final secondBody = await utf8.decodeStream(secondRes);
    final secondParts = secondBody.split('|');

    expect(secondParts[0], isNot(firstParts[0]));
    expect(secondParts[1], 'true');
  });

  test('NativeHttpServer autoCompress sends gzip when accepted', () async {
    final server = await NativeHttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      http3: false,
    );
    addTearDown(() => server.close(force: true));
    server.autoCompress = true;

    final payload = List<String>.filled(
      256,
      'server native payload line',
    ).join('\n');
    // ignore: discarded_futures
    server.listen((request) async {
      request.response.write(payload);
      await request.response.close();
    });

    final client = HttpClient()..autoUncompress = false;
    addTearDown(() => client.close(force: true));
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/gzip'),
    );
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    final res = await req.close();
    final compressedBytes = await res.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    final compressedPayload = compressedBytes.takeBytes();
    final decoded = utf8.decode(gzip.decode(compressedPayload));

    final contentEncoding = res.headers.value(
      HttpHeaders.contentEncodingHeader,
    );
    if (contentEncoding != null) {
      expect(contentEncoding, 'gzip');
    }
    expect(compressedPayload[0], 0x1f);
    expect(compressedPayload[1], 0x8b);
    expect(decoded, payload);

    final reqNoGzip = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/plain'),
    );
    reqNoGzip.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final resNoGzip = await reqNoGzip.close();
    final plainBytes = await resNoGzip.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    final plainPayload = plainBytes.takeBytes();
    expect(resNoGzip.headers.value(HttpHeaders.contentEncodingHeader), isNull);
    expect(plainPayload[0] == 0x1f && plainPayload[1] == 0x8b, isFalse);
  });
}
