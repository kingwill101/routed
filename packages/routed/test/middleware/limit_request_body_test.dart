import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('limitRequestBody middleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

        test('rejects payloads larger than configured limit', () async {
          final engine = Engine()
            ..post(
              '/upload',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(10)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/upload',
            List<int>.filled(11, 120),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['11'],
            },
          );
          response.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('allows payloads within the limit', () async {
          final engine = Engine()
            ..post(
              '/upload',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(16)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/upload',
            List<int>.filled(9, 120),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['9'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('allows payloads exactly at the limit', () async {
          final engine = Engine()
            ..post(
              '/exact',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(100)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/exact',
            List<int>.filled(100, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['100'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('rejects when Content-Length exceeds limit', () async {
          final engine = Engine()
            ..post(
              '/size-check',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(50)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/size-check',
            List<int>.filled(51, 88),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['51'],
            },
          );
          response.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('handles zero-byte payloads', () async {
          final engine = Engine()
            ..post(
              '/empty',
              (ctx) => ctx.string('empty ok'),
              middlewares: [limitRequestBody(100)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/empty',
            '',
            headers: {
              'Content-Type': ['text/plain'],
              HttpHeaders.contentLengthHeader: ['0'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('empty ok');
        });

        test('works with very small limits', () async {
          final engine = Engine()
            ..post(
              '/tiny',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(1)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // Should accept 1 byte
          final okResponse = await client.post(
            '/tiny',
            'A',
            headers: {
              'Content-Type': ['text/plain'],
              HttpHeaders.contentLengthHeader: ['1'],
            },
          );
          okResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');

          // Should reject 2 bytes
          final tooLargeResponse = await client.post(
            '/tiny',
            'AB',
            headers: {
              'Content-Type': ['text/plain'],
              HttpHeaders.contentLengthHeader: ['2'],
            },
          );
          tooLargeResponse.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('works with large limits', () async {
          final engine = Engine()
            ..post(
              '/large',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(1024 * 1024)], // 1MB
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/large',
            List<int>.filled(1000, 77),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['1000'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('different routes can have different limits', () async {
          final engine = Engine()
            ..post(
              '/small-limit',
              (ctx) => ctx.string('small ok'),
              middlewares: [limitRequestBody(10)],
            )
            ..post(
              '/large-limit',
              (ctx) => ctx.string('large ok'),
              middlewares: [limitRequestBody(100)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // 50 bytes should fail small-limit but pass large-limit
          final payload = List<int>.filled(50, 99);

          final smallResponse = await client.post(
            '/small-limit',
            payload,
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['50'],
            },
          );
          smallResponse.assertStatus(HttpStatus.requestEntityTooLarge);

          final largeResponse = await client.post(
            '/large-limit',
            payload,
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['50'],
            },
          );
          largeResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('large ok');
        });

        test('applies to PUT requests', () async {
          final engine = Engine()
            ..put(
              '/update',
              (ctx) => ctx.string('updated'),
              middlewares: [limitRequestBody(20)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          final okResponse = await client.put(
            '/update',
            List<int>.filled(15, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['15'],
            },
          );
          okResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('updated');

          final tooLargeResponse = await client.put(
            '/update',
            List<int>.filled(25, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['25'],
            },
          );
          tooLargeResponse.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('applies to PATCH requests', () async {
          final engine = Engine()
            ..patch(
              '/partial',
              (ctx) => ctx.string('patched'),
              middlewares: [limitRequestBody(30)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          final okResponse = await client.patch(
            '/partial',
            List<int>.filled(25, 80),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['25'],
            },
          );
          okResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('patched');

          final tooLargeResponse = await client.patch(
            '/partial',
            List<int>.filled(35, 80),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['35'],
            },
          );
          tooLargeResponse.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('handles JSON payloads', () async {
          final engine = Engine()
            ..post(
              '/json',
              (ctx) => ctx.json({'received': true}),
              middlewares: [limitRequestBody(50)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // Small JSON should work
          final smallJson = '{"name":"test"}';
          final okResponse = await client.post(
            '/json',
            smallJson,
            headers: {
              'Content-Type': ['application/json'],
              HttpHeaders.contentLengthHeader: ['${smallJson.length}'],
            },
          );
          okResponse
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('received', true);

          // Large JSON should fail
          final largeJson = '{"name":"${'x' * 100}"}';
          final tooLargeResponse = await client.post(
            '/json',
            largeJson,
            headers: {
              'Content-Type': ['application/json'],
              HttpHeaders.contentLengthHeader: ['${largeJson.length}'],
            },
          );
          tooLargeResponse.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('works with middleware chain', () async {
          var otherMiddlewareExecuted = false;

          Future<Response> testMiddleware(EngineContext ctx, Next next) async {
            otherMiddlewareExecuted = true;
            return next();
          }

          final engine = Engine()
            ..post(
              '/chained',
              (ctx) => ctx.string('ok'),
              middlewares: [testMiddleware, limitRequestBody(100)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/chained',
            List<int>.filled(50, 77),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['50'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');

          expect(otherMiddlewareExecuted, isTrue);
        });

        test('short-circuits middleware chain when limit exceeded', () async {
          var handlerExecuted = false;

          final engine = Engine()
            ..post('/short-circuit', (ctx) {
              handlerExecuted = true;
              return ctx.string('ok');
            }, middlewares: [limitRequestBody(10)]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/short-circuit',
            List<int>.filled(20, 88),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['20'],
            },
          );
          response.assertStatus(HttpStatus.requestEntityTooLarge);

          expect(handlerExecuted, isFalse);
        });

        test('does not affect GET requests', () async {
          final engine = Engine()
            ..get(
              '/get-test',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(10)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/get-test');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('handles requests without Content-Length header', () async {
          final engine = Engine()
            ..post(
              '/no-length',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(100)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.post(
            '/no-length',
            'small data',
            headers: {
              'Content-Type': ['text/plain'],
            },
          );
          // Should allow request without Content-Length or check actual body size
          response.assertStatus(HttpStatus.ok);
        });

        test('sequential requests maintain independent limits', () async {
          final engine = Engine()
            ..post(
              '/sequential',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(50)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          // First request within limit
          final response1 = await client.post(
            '/sequential',
            List<int>.filled(30, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['30'],
            },
          );
          response1
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');

          // Second request exceeds limit
          final response2 = await client.post(
            '/sequential',
            List<int>.filled(60, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['60'],
            },
          );
          response2.assertStatus(HttpStatus.requestEntityTooLarge);

          // Third request within limit again
          final response3 = await client.post(
            '/sequential',
            List<int>.filled(40, 65),
            headers: {
              'Content-Type': ['application/octet-stream'],
              HttpHeaders.contentLengthHeader: ['40'],
            },
          );
          response3
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('limit of zero rejects all non-empty payloads', () async {
          final engine = Engine()
            ..post(
              '/zero-limit',
              (ctx) => ctx.string('ok'),
              middlewares: [limitRequestBody(0)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          final response = await client.post(
            '/zero-limit',
            'A',
            headers: {
              'Content-Type': ['text/plain'],
              HttpHeaders.contentLengthHeader: ['1'],
            },
          );
          response.assertStatus(HttpStatus.requestEntityTooLarge);
        });

        test('handles multipart form data within limit', () async {
          final engine = Engine()
            ..post(
              '/multipart',
              (ctx) => ctx.string('uploaded'),
              middlewares: [limitRequestBody(500)],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final payload = List<int>.filled(100, 66);
          final response = await client.post(
            '/multipart',
            payload,
            headers: {
              'Content-Type': [
                'multipart/form-data; boundary=----WebKitFormBoundary',
              ],
              HttpHeaders.contentLengthHeader: ['${payload.length}'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('uploaded');
        });
      });
    }
  });
}
