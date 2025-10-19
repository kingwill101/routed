import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_testing/server_testing.dart';

/// Define a suite of routes that stress transport and mocks using engineGroup
/// and engineTest with both inMemory and ephemeral modes.
void main() {
  FutureOr<void> onRequest(HttpRequest req) async {
    switch ('${req.method} ${req.uri.path}') {
      case 'GET /json':
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(
          'Content-Type',
          'application/json; charset=utf-8',
        );
        req.response.write('{"ok":true,"n":1}');
        break;
      case 'POST /echo':
        final body = await utf8.decoder.bind(req).join();
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.text;
        req.response.write(body);
        break;
      case 'GET /slow':
        await Future<void>.delayed(const Duration(milliseconds: 50));
        req.response.statusCode = HttpStatus.ok;
        req.response.write('late');
        break;
      case 'GET /head':
      case 'HEAD /head':
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.text;
        if (req.method != 'HEAD') {
          req.response.write('body');
        }
        break;
      case 'GET /set-cookie':
        req.response.cookies.add(Cookie('a', '1'));
        req.response.cookies.add(Cookie('b', '2'));
        req.response.statusCode = HttpStatus.ok;
        req.response.write('ok');
        break;
      case 'PUT /json':
        // Ensure Content-Type preserved
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set('Content-Type', 'application/json');
        req.response.write('{"updated":true}');
        break;
      case 'DELETE /nobody':
        req.response.statusCode = HttpStatus.noContent;
        break;
      case 'OPTIONS /preflight':
        req.response.statusCode = HttpStatus.noContent;
        req.response.headers.set(
          'Access-Control-Allow-Origin',
          'https://client.dev',
        );
        req.response.headers.set(
          'Access-Control-Allow-Methods',
          'GET, POST, PUT',
        );
        break;
      case 'GET /stream':
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.text;
        req.response.write('part1');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        req.response.write('part2');
        break;
      case 'GET /multi-cookie':
        req.response.statusCode = HttpStatus.ok;
        req.response.cookies.add(Cookie('one', '1'));
        req.response.cookies.add(Cookie('two', '2'));
        break;
      case 'GET /header-case':
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.add('X-Custom-Header', 'Value');
        req.response.headers.add('x-custom-header', 'Value2');
        break;
      case 'GET /set-multi-set-cookie':
        req.response.statusCode = HttpStatus.ok;
        // Explicit Set-Cookie header values
        req.response.headers.add('Set-Cookie', 'a=1; Path=/');
        req.response.headers.add('Set-Cookie', 'b=2; Path=/');
        break;
      default:
        req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  }

  for (final mode in TransportMode.values) {
    group('IO route harness [$mode]', () {
      final handler = IoRequestHandler(onRequest);
      Future<TestClient> mk() async => TestClient(handler, mode: mode);

      test('PUT /json returns JSON response', () async {
        final client = await mk();
        final r = await client.put('/json', '{}');
        r
            .assertStatus(200)
            .assertHeaderContains(
              HttpHeaders.contentTypeHeader,
              'application/json',
            );
        await client.close();
      });

      test('DELETE /nobody returns 204 with no body', () async {
        final client = await mk();
        final r = await client.delete('/nobody');
        r.assertStatus(HttpStatus.noContent).assertNoBody();
        await client.close();
      });

      test('OPTIONS /preflight returns CORS headers', () async {
        final client = await mk();
        final r = await client.options('/preflight');
        r
          ..assertStatus(HttpStatus.noContent)
          ..assertHeaderContains(
            'Access-Control-Allow-Origin',
            'https://client.dev',
          )
          ..assertHeaderContains('Access-Control-Allow-Methods', 'POST');
        await client.close();
      });

      test('GET /stream concatenates writes', () async {
        final client = await mk();
        final r = await client.get('/stream');
        r
            .assertStatus(200)
            .assertBodyContains('part1')
            .assertBodyContains('part2');
        await client.close();
      });

      test('GET /multi-cookie reflected in Set-Cookie', () async {
        final client = await mk();
        final r = await client.get('/multi-cookie');
        r.assertStatus(200).assertHasHeader(HttpHeaders.setCookieHeader);
        final setCookies = r.headers[HttpHeaders.setCookieHeader]!;
        expect(setCookies.length, greaterThanOrEqualTo(2));
        expect(setCookies.any((c) => c.startsWith('one=')), isTrue);
        expect(setCookies.any((c) => c.startsWith('two=')), isTrue);
        await client.close();
      });

      test('duplicate header names are retained', () async {
        final client = await mk();
        final r = await client.get('/header-case');
        r
            .assertStatus(200)
            .assertHasHeader('X-Custom-Header')
            .assertHeaderContains('X-Custom-Header', ['Value', 'Value2']);
        await client.close();
      });

      test('explicit Set-Cookie header values preserved', () async {
        final client = await mk();
        final r = await client.get('/set-multi-set-cookie');
        r.assertStatus(200).assertHasHeader(HttpHeaders.setCookieHeader);
        final setCookies = r.headers.entries
            .firstWhere(
              (e) => e.key.toLowerCase() == HttpHeaders.setCookieHeader,
            )
            .value;
        expect(setCookies.any((v) => v.contains('a=1; Path=/')), isTrue);
        expect(setCookies.any((v) => v.contains('b=2; Path=/')), isTrue);
        await client.close();
      });

      test('GET /json returns JSON', () async {
        final client = await mk();
        final r = await client.get('/json');
        r
            .assertStatus(200)
            .assertHeaderContains(
              HttpHeaders.contentTypeHeader,
              'application/json',
            );
        r.assertJson((j) => j.has('ok').equals('n', 1));
        await client.close();
      });

      test('POST /echo echoes body', () async {
        final client = await mk();
        final r = await client.post('/echo', 'hello');
        r.assertStatus(200).assertBodyEquals('hello');
        await client.close();
      });

      test('HEAD has empty body but 200 status', () async {
        final client = await mk();
        final getR = await client.get('/head');
        final headR = await client.head('/head');
        expect(getR.statusCode, 200);
        expect(headR.statusCode, 200);
        expect(headR.body, '');
        await client.close();
      });

      test('multiple Set-Cookie preserved', () async {
        final client = await mk();
        final r = await client.get('/set-cookie');
        r.assertStatus(200).assertHasHeader(HttpHeaders.setCookieHeader);
        final setCookies = r.headers[HttpHeaders.setCookieHeader]!;
        expect(setCookies.length, equals(2));
        expect(setCookies.any((c) => c.startsWith('a=')), isTrue);
        expect(setCookies.any((c) => c.startsWith('b=')), isTrue);
        await client.close();
      });
    });
  }
}
