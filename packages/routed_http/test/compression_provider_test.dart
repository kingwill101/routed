import 'dart:convert';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_http/routed_http.dart';
import 'package:test/test.dart';

void main() {
  test('compresses eligible JSON when gzip is accepted', () async {
    final engine = await Engine.create(
      providers: [
        RoutedCompressionProvider(
          CompressionConfig(enabled: true, minLength: 1),
        ),
      ],
    );
    addTearDown(engine.close);
    final payload = 'payload' * 400;
    engine.get('/payload', (ctx) => ctx.json({'payload': payload}));

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/payload'),
        headers: PortableHeaders({
          HttpHeaders.acceptEncodingHeader: ['br, gzip;q=0.8'],
        }),
      ),
    );

    expect(response.headers.get(HttpHeaders.contentEncodingHeader), 'gzip');
    expect(response.headers.get(HttpHeaders.varyHeader), 'accept-encoding');
    expect(
      int.parse(response.headers.get(HttpHeaders.contentLengthHeader)!),
      response.bodyBytes!.length,
    );
    final decoded = utf8.decode(gzip.decode(response.bodyBytes!));
    expect(decoded, contains(payload));
  });

  test('does not compress when the client does not accept gzip', () async {
    final engine = await Engine.create(
      providers: [
        RoutedCompressionProvider(
          CompressionConfig(enabled: true, minLength: 1),
        ),
      ],
    );
    addTearDown(engine.close);
    engine.get('/payload', (ctx) => ctx.json({'payload': 'payload' * 400}));

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/payload'),
        headers: PortableHeaders({
          HttpHeaders.acceptEncodingHeader: ['identity'],
        }),
      ),
    );

    expect(response.headers.get(HttpHeaders.contentEncodingHeader), isNull);
    expect(response.bodyText, contains('payload'));
  });

  test('does not label streamed responses as compressed', () async {
    final engine = await Engine.create(
      providers: [
        RoutedCompressionProvider(
          CompressionConfig(enabled: true, minLength: 1),
        ),
      ],
    );
    addTearDown(engine.close);
    engine.get('/stream', (ctx) async {
      await ctx.response.addStream(
        Stream<List<int>>.value(utf8.encode('streamed' * 400)),
      );
      return ctx.response;
    });

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/stream'),
        headers: PortableHeaders({
          HttpHeaders.acceptEncodingHeader: ['gzip'],
        }),
      ),
    );

    expect(response.headers.get(HttpHeaders.contentEncodingHeader), isNull);
    expect(response.bodyText, startsWith('streamed'));
  });

  test('rejects invalid configuration before provider boot', () {
    expect(
      Engine.create(
        providers: [
          RoutedCompressionProvider(CompressionConfig(minLength: -1)),
        ],
      ),
      throwsA(isA<ConfigValidationException>()),
    );
  });

  test('keeps list settings immutable after construction', () {
    final algorithms = ['gzip'];
    final config = CompressionConfig(algorithms: algorithms);

    algorithms.add('br');

    expect(config.algorithms, ['gzip']);
    expect(() => config.algorithms.add('br'), throwsUnsupportedError);
  });
}
