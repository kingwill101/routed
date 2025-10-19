import 'dart:convert';
import 'dart:io';

import 'package:es_compression/brotli.dart' as es_brotli;
import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('compressionMiddleware', () {
    final modes = TransportMode.values
        .where((mode) => mode != TransportMode.inMemory)
        .toList();

    for (final mode in modes) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

        test(
          'compresses eligible text responses when client accepts gzip',
          () async {
            final body = 'Hello world! ' * 20;
            final engine = Engine(
              configItems: {
                'compression': {'min_length': 8},
              },
            )..get('/greet', (ctx) => ctx.string(body));

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get(
              '/greet',
              headers: {
                HttpHeaders.acceptEncodingHeader: ['gzip'],
              },
            );

            response
              ..assertHeaderContains(HttpHeaders.contentEncodingHeader, 'gzip')
              ..assertHeaderContains('Vary', 'Accept-Encoding');

            final decoded = GZipCodec().decode(response.bodyBytes);
            expect(utf8.decode(decoded), equals(body));
          },
        );

        test('prefers brotli when weighted higher by the client', () async {
          final body = 'Brotli beats gzip when the client prefers it.' * 10;
          String? seenAcceptEncoding;
          final engine =
              Engine(
                configItems: {
                  'compression': {'min_length': 8},
                },
              )..get('/br', (ctx) {
                seenAcceptEncoding = ctx.request.headers.value(
                  HttpHeaders.acceptEncodingHeader,
                );
                return ctx.string(body);
              });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get(
            '/br',
            headers: {
              HttpHeaders.acceptEncodingHeader: ['br;q=1.0, gzip;q=0.5'],
            },
          );

          expect(seenAcceptEncoding, isNotNull);
          response.assertHeaderContains(
            HttpHeaders.contentEncodingHeader,
            'br',
          );
          final decoded = es_brotli.brotli.decode(response.bodyBytes);
          expect(utf8.decode(decoded), equals(body));
        });

        test('skips compression for disallowed mime types', () async {
          final body = 'PNG data but represented as text for the test.' * 10;
          final engine =
              Engine(
                configItems: {
                  'compression': {
                    'min_length': 8,
                    'mime_allow': ['text/'],
                    'mime_deny': ['image/'],
                  },
                },
              )..get('/image', (ctx) {
                ctx.response.headers.set(
                  HttpHeaders.contentTypeHeader,
                  'image/png',
                );
                return ctx.string(body);
              });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get(
            '/image',
            headers: {
              HttpHeaders.acceptEncodingHeader: ['gzip, br'],
            },
          );

          expect(response.headers[HttpHeaders.contentEncodingHeader], isNull);
          expect(response.body, equals(body));
        });

        test(
          'honours disableCompression helper on a per-route basis',
          () async {
            final body = 'Do not compress this response.' * 10;
            final engine =
                Engine(
                  configItems: {
                    'compression': {'min_length': 8},
                  },
                )..get('/skip', (ctx) {
                  disableCompression(ctx);
                  return ctx.string(body);
                });

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get(
              '/skip',
              headers: {
                HttpHeaders.acceptEncodingHeader: ['gzip'],
              },
            );

            expect(response.headers[HttpHeaders.contentEncodingHeader], isNull);
            expect(response.body, equals(body));
          },
        );

        test(
          'skips compression when body is smaller than the configured minimum',
          () async {
            const body = 'tiny';
            final engine = Engine(
              configItems: {
                'compression': {'min_length': 1024},
              },
            )..get('/small', (ctx) => ctx.string(body));

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get(
              '/small',
              headers: {
                HttpHeaders.acceptEncodingHeader: ['gzip'],
              },
            );

            expect(response.headers[HttpHeaders.contentEncodingHeader], isNull);
            expect(response.body, equals(body));
          },
        );
      });
    }
  });
}
