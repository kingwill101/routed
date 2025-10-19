import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('conditionalRequests middleware', () {
    late Engine engine;
    late TestClient client;

    setUp(() async {
      engine = Engine();

      engine.get(
        '/article',
        (ctx) => ctx.json({'message': 'ok'}),
        middlewares: [
          conditionalRequests(
            etag: (_) => '"etag-resource"',
            lastModified: (_) => DateTime.utc(2024, 01, 01, 12),
          ),
        ],
      );

      await engine.initialize();

      client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
    });

    tearDown(() async {
      await client.close();
      await engine.close();
    });

    test('returns 304 when validators match', () async {
      final response = await client.get(
        '/article',
        headers: {
          HttpHeaders.ifNoneMatchHeader: ['"etag-resource"'],
        },
      );

      response.assertStatus(HttpStatus.notModified);
      expect(
        response.headers[HttpHeaders.etagHeader]?.first,
        equals('"etag-resource"'),
      );
    });

    test('returns 412 when preconditions fail', () async {
      final response = await client.get(
        '/article',
        headers: {
          HttpHeaders.ifMatchHeader: ['"different"'],
        },
      );

      response.assertStatus(HttpStatus.preconditionFailed);
    });

    test('passes through when validators do not match', () async {
      final response = await client.get('/article');

      response
        ..assertStatus(HttpStatus.ok)
        ..assertHasHeader(HttpHeaders.etagHeader)
        ..assertHasHeader(HttpHeaders.lastModifiedHeader);
    });
  });
}
