@Tags(['property'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:property_testing/property_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('TestClient cookie persistence', () {
    final nameGen = Gen.string(minLength: 1, maxLength: 8);
    final valueGen = Gen.string(minLength: 0, maxLength: 12);

    final cookieListGen = nameGen
        .flatMap((name) => valueGen.map((value) => (name: name, value: value)))
        .list(minLength: 1, maxLength: 4);

    test('Set-Cookie directives persist across requests (property)', () async {
      final runner = PropertyTestRunner<List<({String name, String value})>>(
        cookieListGen,
        (samples) async {
          final handler = _CookieEchoHandler();
          final client = TestClient.inMemory(handler);

          final expected = <String, String>{};
          try {
            for (final sample in samples) {
              expected[sample.name] = sample.value;
              final response = await client.get(
                '/set?name=${Uri.encodeComponent(sample.name)}&value=${Uri.encodeComponent(sample.value)}',
              );
              response.assertStatus(HttpStatus.ok);
            }

            final inspect = await client.get('/inspect');
            inspect
                .assertStatus(HttpStatus.ok)
                .assertHeaderContains(
                  HttpHeaders.contentTypeHeader,
                  'application/json',
                );

            final payload = (inspect.json() as Map).cast<String, dynamic>().map(
              (key, value) => MapEntry(key, value as String),
            );
            expect(payload, equals(expected));
          } finally {
            await client.close();
            await handler.close();
          }
        },
        PropertyConfig(numTests: 40, seed: 20250311),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });
  });
}

class _CookieEchoHandler implements RequestHandler {
  @override
  Future<void> handleRequest(HttpRequest request) async {
    if (request.uri.path == '/set') {
      final name = request.uri.queryParameters['name'];
      final value = request.uri.queryParameters['value'];
      if (name == null || value == null) {
        request.response.statusCode = HttpStatus.badRequest;
      } else {
        request.response.cookies.add(Cookie(name, value));
        request.response.statusCode = HttpStatus.ok;
      }
      await request.response.close();
      return;
    }

    if (request.uri.path == '/inspect') {
      request.response.headers.contentType = ContentType.json;
      final cookies = {
        for (final cookie in request.cookies) cookie.name: cookie.value,
      };
      request.response.write(jsonEncode(cookies));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  @override
  Future<int> startServer({int port = 0}) async => port;

  @override
  Future<void> close([bool force = true]) async {}
}
