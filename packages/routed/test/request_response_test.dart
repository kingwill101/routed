import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

Future<({Engine engine, TestClient client})> _setupClient({
  EngineConfig? config,
}) async {
  final engine = await Engine.create(
    config: config,
    providers: [
      CoreServiceProvider(
        configItems: const {'app.name': 'Test App', 'app.env': 'testing'},
      ),
      RoutingServiceProvider(),
    ],
  );
  final client = TestClient(
    RoutedRequestHandler(engine),
    mode: TransportMode.ephemeralServer,
  );
  addTearDown(() async {
    await client.close();
    await engine.close();
  });
  return (engine: engine, client: client);
}

void main() {
  group('Request', () {
    test('reads body and caches bytes', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.post('/body', (ctx) async {
        final body = await ctx.request.body();
        final firstBytes = await ctx.request.bytes;
        final secondBytes = await ctx.request.bytes;
        return ctx.json({
          'body': body,
          'cached': identical(firstBytes, secondBytes),
          'header': ctx.request.header('X-Test'),
        });
      });

      final response = await client.post(
        '/body',
        'hello',
        headers: {
          'X-Test': ['one', 'two'],
        },
      );

      expect(response.json()['body'], equals('hello'));
      expect(response.json()['cached'], isTrue);
      expect(response.json()['header'], equals('one, two'));
    });

    test('does not consume body when handler does not read it', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;
      bool? consumed;

      engine.post('/no-read', (ctx) {
        consumed = ctx.request.bodyConsumed;
        return ctx.string('ok');
      });

      final response = await client.post('/no-read', 'payload');
      response.assertStatus(HttpStatus.ok);

      expect(consumed, isFalse);
    });

    test('marks body as consumed after reading bytes', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.post('/read', (ctx) async {
        await ctx.request.bytes;
        return ctx.json({'consumed': ctx.request.bodyConsumed});
      });

      final response = await client.post('/read', 'payload');

      expect(response.json()['consumed'], isTrue);
    });

    test('overrides client IP from trusted platform header', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/ip', (ctx) {
        final header = ctx.request.header(EngineConfig.platformCloudflare);
        if (header.isNotEmpty) {
          ctx.request.overrideClientIp(header);
        }
        return ctx.string(ctx.request.clientIP);
      });

      final response = await client.get(
        '/ip',
        headers: {
          EngineConfig.platformCloudflare: ['203.0.113.10'],
        },
      );

      expect(response.body, equals('203.0.113.10'));
    });

    test('overrides client IP from forwarded header', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/ip', (ctx) {
        final header = ctx.request.header('X-Forwarded-For');
        if (header.isNotEmpty) {
          ctx.request.overrideClientIp(header.split(',').first.trim());
        }
        return ctx.string(ctx.request.clientIP);
      });

      final response = await client.get(
        '/ip',
        headers: {
          'X-Forwarded-For': ['198.51.100.5'],
        },
      );

      expect(response.body, equals('198.51.100.5'));
    });

    test('returns remote address when proxy support disabled', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/ip', (ctx) {
        final before = ctx.request.clientIP;
        ctx.request.overrideClientIp('203.0.113.8');
        final after = ctx.request.clientIP;
        return ctx.json({'before': before, 'after': after});
      });

      final response = await client.get(
        '/ip',
        headers: {
          'X-Forwarded-For': ['198.51.100.5'],
        },
      );

      expect(response.json()['before'], equals('127.0.0.1'));
      expect(response.json()['after'], equals('203.0.113.8'));
    });

    test('exposes metadata and attributes', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.post('/meta', (ctx) async {
        ctx.request.setAttribute('user', 'alice');
        final attributeBefore = ctx.request.getAttribute<String>('user');
        ctx.request.clearAttributes();
        final attributeAfter = ctx.request.getAttribute<String>('user');
        final body = await ctx.request.body();

        return ctx.json({
          'method': ctx.request.method,
          'contentLength': ctx.request.contentLength,
          'path': ctx.request.uri.path,
          'requestedScheme': ctx.request.requestedUri.scheme,
          'host': ctx.request.host,
          'scheme': ctx.request.scheme,
          'remoteAddr': ctx.request.remoteAddr,
          'query': ctx.request.queryParameters['query'],
          'protocol': ctx.request.protocolVersion,
          'cookie': ctx.request.cookies.first.value,
          'persistent': ctx.request.persistentConnection,
          'contentType': ctx.request.contentType?.mimeType,
          'attributeBefore': attributeBefore,
          'attributeAfter': attributeAfter,
          'body': body,
        });
      });

      final response = await client.post(
        '/meta?query=1',
        'payload',
        headers: {
          'Content-Type': ['application/json; charset=utf-8'],
          'Cookie': ['token=abc'],
        },
      );

      expect(response.json()['method'], equals('POST'));
      expect(response.json()['contentLength'], equals(-1));
      expect(response.json()['path'], equals('/meta'));
      expect(response.json()['requestedScheme'], equals('http'));
      expect(response.json()['host'], contains('127.0.0.1'));
      expect(response.json()['scheme'], equals(''));
      expect(response.json()['remoteAddr'], equals('127.0.0.1'));
      expect(response.json()['query'], equals('1'));
      expect(response.json()['protocol'], equals('1.1'));
      expect(response.json()['cookie'], equals('abc'));
      expect(response.json()['persistent'], isTrue);
      expect(response.json()['contentType'], equals('application/json'));
      expect(response.json()['attributeBefore'], equals('alice'));
      expect(response.json()['attributeAfter'], isNull);
      expect(response.json()['body'], equals('payload'));
    });
  });

  group('Response', () {
    test(
      'string/json responses set content-length without chunked encoding',
      () async {
        final setup = await _setupClient();
        final engine = setup.engine;
        final client = setup.client;

        engine.get('/plain', (ctx) => ctx.string('ok'));
        engine.get('/json', (ctx) => ctx.json({'ok': true}));

        final plain = await client.get('/plain');
        plain
          ..assertStatus(HttpStatus.ok)
          ..assertHeader('content-length', '2')
          ..assertMissingHeader('transfer-encoding');

        final jsonResponse = await client.get('/json');
        jsonResponse
          ..assertStatus(HttpStatus.ok)
          ..assertMissingHeader('transfer-encoding');
        expect(jsonResponse.header('content-length'), isNotEmpty);
      },
    );

    test('writes headers, cookies, and filtered body', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/headers', (ctx) {
        ctx.response.addHeader('X-Test', 'one');
        ctx.response.addHeader('X-Test', 'two');
        ctx.response.addHeader(HttpHeaders.setCookieHeader, 'legacy=1');
        ctx.response.setCookie('session', 'abc', maxAge: 10, httpOnly: true);
        ctx.response.setBodyFilter((body) {
          return utf8.encode(utf8.decode(body).toUpperCase());
        });
        ctx.response.write('hello');
        ctx.response.writeNow();
        ctx.response.statusCode = HttpStatus.created;
        ctx.response.close();
        return ctx.response;
      });

      final response = await client.get('/headers');

      expect(response.body, equals('HELLO'));
      expect(response.header('X-Test').single, equals('one, two'));
      expect(response.cookie('session')?.value, equals('abc'));
      expect(
        response.header(HttpHeaders.setCookieHeader).join('; '),
        contains('legacy=1'),
      );
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('writes string, json, and error responses', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/string', (ctx) async {
        await ctx.response.string('hi');
        return ctx.response;
      });
      engine.get('/json', (ctx) async {
        await ctx.response.json({'ok': true});
        return ctx.response;
      });
      engine.get('/error', (ctx) {
        ctx.response.error('fail', statusCode: HttpStatus.badRequest);
        return ctx.response;
      });

      final stringResponse = await client.get('/string');
      expect(stringResponse.body, equals('hi'));

      final jsonResponse = await client.get('/json');
      expect(jsonResponse.json()['ok'], isTrue);
      jsonResponse.assertHeaderContains('content-type', 'application/json');

      final errorResponse = await client.get('/error');
      expect(errorResponse.body, equals('fail'));
      expect(errorResponse.statusCode, equals(HttpStatus.badRequest));
    });

    test('streams bytes and manages headers', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/bytes', (ctx) {
        ctx.response.writeBytes([1, 2, 3]);
        ctx.response.writeNow();
        ctx.response.close();
        return ctx.response;
      });

      engine.get('/stream', (ctx) async {
        ctx.response.setHeader('X-Mode', 'stream');
        ctx.response.removeHeader('X-Mode');
        await ctx.response.addStream(
          Stream.fromIterable([utf8.encode('a'), utf8.encode('b')]),
        );
        ctx.response.close();
        return ctx.response;
      });

      final buffered = await client.get('/bytes');
      expect(buffered.bodyBytes, equals([1, 2, 3]));

      final streamed = await client.get('/stream');
      expect(streamed.headers.containsKey('X-Mode'), isFalse);
      expect(streamed.body, equals('ab'));
    });

    test('flushes buffered content', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/flush', (ctx) async {
        ctx.response.write('pong');
        await ctx.response.flush();
        ctx.response.close();
        return ctx.response;
      });

      final response = await client.get('/flush');
      expect(response.body, equals('pong'));
    });

    test('download streams file and redirect sets location', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;
      final tempDir = await Directory.systemTemp.createTemp('routed_download');

      final file = File('${tempDir.path}/payload.txt');
      await file.writeAsString('payload');

      engine.get('/download', (ctx) {
        ctx.response.download(
          file,
          name: 'download.txt',
          headers: {'X-File': 'yes'},
        );
        return ctx.response;
      });
      engine.get('/redirect', (ctx) {
        ctx.response.redirect(
          '/next',
          status: HttpStatus.movedPermanently,
          headers: {'X-Redirect': '1'},
        );
        return ctx.response;
      });
      engine.get('/next', (ctx) => ctx.string('next'));

      addTearDown(() async {
        await tempDir.delete(recursive: true);
      });

      final downloadResponse = await client.get('/download');
      downloadResponse.assertHeaderContains(
        'content-disposition',
        'download.txt',
      );
      downloadResponse.assertHeaderContains(
        HttpHeaders.contentTypeHeader,
        'application/octet-stream',
      );
      downloadResponse.assertHeaderContains('x-file', 'yes');
      expect(downloadResponse.body, equals('payload'));

      final redirectResponse = await client.get('/redirect');
      expect(redirectResponse.statusCode, equals(HttpStatus.ok));
      expect(redirectResponse.body, equals('next'));
    });

    test('updates cookies and removes headers', () async {
      final setup = await _setupClient();
      final engine = setup.engine;
      final client = setup.client;

      engine.get('/cookies', (ctx) {
        ctx.response.setCookie('session', 'one');
        ctx.response.setCookie('session', 'two');
        ctx.response.write('ok');
        ctx.response.close();
        ctx.response.setBodyFilter((body) => body.reversed.toList());
        return ctx.response;
      });
      engine.get('/remove-header', (ctx) {
        ctx.response.addHeader('X-Trace', 'alpha');
        ctx.response.removeHeader('X-Trace', value: 'alpha');
        ctx.response.write('done');
        ctx.response.close();
        return ctx.response;
      });

      final cookieResponse = await client.get('/cookies');
      expect(cookieResponse.cookie('session')?.value, equals('two'));

      final headerResponse = await client.get('/remove-header');
      expect(headerResponse.headers.containsKey('X-Trace'), isFalse);
      expect(headerResponse.body, equals('done'));
    });
  });
}
