// Explicit setup calls keep XML binding scenarios readable.
// ignore_for_file: cascade_invocations
import 'package:routed_core/routed_core.dart';
import 'package:routed_http/routed_http.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'test_engine.dart';

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  test('default binding decodes application/xml object bodies', () async {
    final engine = testEngine();
    engine.post('/xml', (context) async {
      final data = <String, dynamic>{};
      await context.bind(data);
      context.json(data);
    });
    client = TestClient(RoutedRequestHandler(engine));

    final response = await client.post(
      '/xml',
      '<user><name>Ada</name><role>admin</role><role>writer</role></user>',
      headers: {
        'Content-Type': ['application/xml'],
      },
    );

    response
      ..assertStatus(200)
      ..assertJsonContains({
        'user': {
          'name': {'#text': 'Ada'},
          'role': [
            {'#text': 'admin'},
            {'#text': 'writer'},
          ],
        },
      });
  });

  test('default binding accepts text/xml', () async {
    expect(defaultBinding('POST', 'text/xml'), same(xmlBinding));
  });

  test('malformed XML is a client error', () async {
    final engine = testEngine();
    engine.post('/xml', (context) async {
      await context.bind(<String, dynamic>{});
      context.string('ok');
    });
    client = TestClient(RoutedRequestHandler(engine));

    final response = await client.post(
      '/xml',
      '<user>',
      headers: {
        'Content-Type': ['application/xml'],
      },
    );

    response.assertStatus(400);
  });

  test('empty XML body binds as an empty map', () async {
    final engine = testEngine();
    engine.post('/xml', (context) async {
      final data = <String, dynamic>{};
      await context.bind(data);
      context.json(data);
    });
    client = TestClient(RoutedRequestHandler(engine));

    final response = await client.post(
      '/xml',
      '',
      headers: {
        'Content-Type': ['application/xml'],
      },
    );

    response
      ..assertStatus(200)
      ..assertJsonContains(<String, dynamic>{});
  });
}
