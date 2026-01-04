import 'dart:convert';
import 'dart:io';

import 'package:es_compression/brotli.dart' as es_brotli;
import 'package:property_testing/property_testing.dart';
import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('compressionMiddleware', () {
    final brotliSupported = isAlgorithmSupported(CompressionAlgorithm.brotli);
    final modes = TransportMode.values
        .where((mode) => mode != TransportMode.inMemory)
        .toList();

    for (final mode in modes) {
      group('with ${mode.name} transport', () {
        test(
          'compresses eligible text responses when client accepts gzip',
          () async {
            final body = 'Hello world! ' * 20;
            final engine = Engine(
              configItems: {
                'compression': {'min_length': 8},
              },
            )..get('/greet', (ctx) => ctx.string(body));

            final client = _startCompressionClient(engine, mode);
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

        test(
          'prefers brotli when weighted higher by the client',
          () async {
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

            final client = _startCompressionClient(engine, mode);
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
          },
          skip: brotliSupported
              ? false
              : 'Brotli not supported on this platform',
        );

        test('skips compression for disallowed mime types', () async {
          final body = 'PNG data but represented as text for the test.' * 10;
          final engine =
              Engine(
                configItems: {
                  'compression': {
                    'min_length': 8,
                    'mime_allow': ['text/*'],
                    'mime_deny': ['image/*'],
                  },
                },
              )..get('/image', (ctx) async {
                ctx.response.headers.contentType = ContentType('image', 'png');
                ctx.response.write(body);
                ctx.response.close();
              });

          final client = _startCompressionClient(engine, mode);
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

            final client = _startCompressionClient(engine, mode);
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

            final client = _startCompressionClient(engine, mode);
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

        test('compression negotiation respects config (property)', () async {
          final runner = PropertyTestRunner<_CompressionSample>(
            _compressionSampleGen(),
            (sample) async {
              final body = 'x' * sample.payloadLength;
              final engine =
                  Engine(
                    configItems: {
                      'compression': {
                        'min_length': sample.minLength,
                        'mime_allow': ['text/*'],
                        'mime_deny': ['image/*'],
                      },
                    },
                  )..get('/resource', (ctx) async {
                    ctx.response.headers.contentType = ContentType.parse(
                      sample.contentType,
                    );
                    if (sample.disableRoute) {
                      disableCompression(ctx);
                    }
                    ctx.response.write(body);
                    ctx.response.close();
                  });

              final client = TestClient(
                RoutedRequestHandler(engine),
                mode: mode,
              );
              final response = await client.get(
                '/resource',
                headers: {
                  HttpHeaders.acceptEncodingHeader: [
                    sample.preferBrotli
                        ? 'br;q=1.0, gzip;q=0.5'
                        : 'gzip;q=1.0, br;q=0.5',
                  ],
                },
              );

              final expectsCompression =
                  sample.contentType.startsWith('text/') &&
                  sample.payloadLength >= sample.minLength &&
                  !sample.disableRoute;

              if (expectsCompression) {
                final expectedEncoding = sample.preferBrotli && brotliSupported
                    ? 'br'
                    : 'gzip';
                response.assertHeaderContains(
                  HttpHeaders.contentEncodingHeader,
                  expectedEncoding,
                );

                final decoded = expectedEncoding == 'br'
                    ? es_brotli.brotli.decode(response.bodyBytes)
                    : GZipCodec().decode(response.bodyBytes);
                expect(utf8.decode(decoded), equals(body));
              } else {
                expect(
                  response.headers[HttpHeaders.contentEncodingHeader],
                  isNull,
                );
                expect(response.body, equals(body));
              }

              await client.close();
              await engine.close();
            },
            PropertyConfig(numTests: 30, seed: 20250316),
          );

          final result = await runner.run();
          expect(result.success, isTrue, reason: result.report);
        });
      });
    }
  });
}

typedef _CompressionSample = ({
  bool preferBrotli,
  int payloadLength,
  int minLength,
  bool disableRoute,
  String contentType,
});

Generator<_CompressionSample> _compressionSampleGen() {
  return Gen.boolean().flatMap(
    (preferBrotli) => Gen.integer(min: 1, max: 256).flatMap(
      (payloadLength) => Gen.integer(min: 1, max: 256).flatMap(
        (minLength) => Gen.boolean().flatMap(
          (disableRoute) => Gen.boolean().map(
            (useText) => (
              preferBrotli: preferBrotli,
              payloadLength: payloadLength,
              minLength: minLength,
              disableRoute: disableRoute,
              contentType: useText ? 'text/plain' : 'image/png',
            ),
          ),
        ),
      ),
    ),
  );
}

TestClient _startCompressionClient(Engine engine, TransportMode mode) {
  final client = TestClient(RoutedRequestHandler(engine), mode: mode);
  addTearDown(client.close);
  addTearDown(engine.close);
  return client;
}
