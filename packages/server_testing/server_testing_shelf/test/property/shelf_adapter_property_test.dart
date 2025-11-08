@Tags(['property'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:property_testing/property_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  group('ShelfRequestHandler property tests', () {
    final segmentGen = Gen.string(minLength: 1, maxLength: 8);
    final segmentListGen = segmentGen.list(minLength: 0, maxLength: 3);

    final pairGen = Gen.string(minLength: 1, maxLength: 6).flatMap(
      (key) => Gen.string(
        minLength: 0,
        maxLength: 10,
      ).map((value) => (key: key, value: value)),
    );

    Generator<Map<String, String>> mapGen({
      required int minLength,
      required int maxLength,
    }) => pairGen.list(minLength: minLength, maxLength: maxLength).map((pairs) {
      final map = <String, String>{};
      for (final pair in pairs) {
        map[pair.key] = pair.value;
      }
      return map;
    });

    final sampleGen = segmentListGen.flatMap(
      (segments) => mapGen(minLength: 0, maxLength: 3).flatMap(
        (query) => mapGen(
          minLength: 0,
          maxLength: 4,
        ).map((body) => (pathSegments: segments, query: query, body: body)),
      ),
    );

    test('request translation preserves path, query, and JSON body', () async {
      final runner =
          PropertyTestRunner<
            ({
              List<String> pathSegments,
              Map<String, String> query,
              Map<String, String> body,
            })
          >(sampleGen, (sample) async {
            final handler = ShelfRequestHandler((request) async {
              final bodyString = await request.readAsString();
              final decoded = bodyString.isEmpty
                  ? const <String, String>{}
                  : (jsonDecode(bodyString) as Map).cast<String, dynamic>().map(
                      (key, value) => MapEntry(key, value as String),
                    );

              return shelf.Response.ok(
                jsonEncode({
                  'path': request.url.path,
                  'query': request.url.queryParameters,
                  'body': decoded,
                }),
                headers: {'content-type': 'application/json'},
              );
            });

            final client = TestClient.inMemory(handler);
            try {
              final encodedPath = sample.pathSegments.isEmpty
                  ? '/'
                  : '/${sample.pathSegments.map(Uri.encodeComponent).join('/')}';

              final queryString = sample.query.entries
                  .map(
                    (entry) =>
                        '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
                  )
                  .join('&');

              final requestPath = queryString.isEmpty
                  ? encodedPath
                  : '$encodedPath?$queryString';

              final response = await client.postJson(requestPath, sample.body);
              response
                  .assertStatus(HttpStatus.ok)
                  .assertHeaderContains(
                    HttpHeaders.contentTypeHeader,
                    'application/json',
                  );

              final payload = (response.json() as Map).cast<String, dynamic>();
              final queryPayload = (payload['query'] as Map)
                  .cast<String, dynamic>();
              final bodyPayload = (payload['body'] as Map)
                  .cast<String, dynamic>();

              expect(payload['path'], equals(sample.pathSegments.join('/')));
              expect(queryPayload, equals(sample.query));
              expect(bodyPayload, equals(sample.body));
            } finally {
              await client.close();
              await handler.close();
            }
          }, PropertyConfig(numTests: 35, seed: 20250312));

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });
  });
}
