import 'dart:convert';

import 'package:http_parser/http_parser.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('ShelfRequestHandler Tests', () {
    test('Basic GET request', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'hello') {
          return shelf.Response.ok('Hello, World!');
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.get('/hello');

      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello, World!');
    });

    test('JSON request and response', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'json' && request.method == 'POST') {
          final payload = jsonDecode(await request.readAsString());
          return shelf.Response.ok(
            jsonEncode({'received': payload, 'success': true}),
            headers: {'content-type': 'application/json'},
          );
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.postJson('/json', {
        'name': 'test',
        'age': 25,
        'tags': ['one', 'two']
      });

      response.dump();
      response

        ..assertStatus(200)
        ..assertJson((json) {
          json
              .has('received')
              .has('success')
              .where('success', true)
              .whereIn('received.tags', ['one', 'two'])
              .where('received.name', 'test')
              .where('received.age', 25);
        });
    });

    test('URL-encoded form submission', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'form' && request.method == 'POST') {
          final contentType = request.headers['content-type'];
          if (contentType?.contains('application/x-www-form-urlencoded') ==
              true) {
            final formData = await request.readAsString();
            final params = Uri.splitQueryString(formData);
            return shelf.Response.ok(
              jsonEncode({'received': params, 'success': true}),
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.post(
        '/form',
        'name=test&age=25',
        headers: {
          'Content-Type': ['application/x-www-form-urlencoded']
        },
      );

      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .has('received')
              .where('received.name', 'test')
              .where('received.age', '25');
        });
    });

    test('Multipart Form submission', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'upload' && request.method == 'POST') {
          if (request.headers['content-type']
                  ?.startsWith('multipart/form-data') ==
              true) {
            final String body = await request.readAsString();

            // For testing, we'll just return some mock data indicating we received the request
            // In a real implementation, you would parse the multipart form
            return shelf.Response.ok(
              jsonEncode({
                'success': true,
                'receivedMultipart': true,
                'contentTypeReceived': request.headers['content-type'],
                'contentLength': request.headers['content-length'],
              }),
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.multipart('/upload', (request) {
        request
          ..addField('name', 'test')
          ..addField('age', '25')
          ..addFileFromBytes(
              name: 'document',
              filename: 'test.txt',
              bytes: utf8.encode('Hello World'),
              contentType: MediaType.parse('text/plain'));
      });

      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .has('success')
              .where('success', true)
              .has('receivedMultipart')
              .where('receivedMultipart', true)
              .has('contentTypeReceived')
              .has('contentLength');
        });
    });

    test('Query parameter handling', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'search') {
          return shelf.Response.ok(
            jsonEncode(request.url.queryParameters),
            headers: {'content-type': 'application/json'},
          );
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.get('/search?q=test&page=1&sort=desc');

      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .has('q')
              .where('q', 'test')
              .has('page')
              .where('page', '1')
              .has('sort')
              .where('sort', 'desc');
        });
    });

    test('Custom status codes and headers', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'custom') {
          return shelf.Response(418, // I'm a teapot
              body: 'Custom response',
              headers: {
                'X-Custom-Header': 'test-value',
                'Content-Type': 'text/plain'
              });
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler));

      final response = await client.get('/custom');

      response
        ..assertStatus(418)
        ..assertBodyEquals('Custom response')
        ..assertHeader('X-Custom-Header', 'test-value')
        ..assertHeader('Content-Type', 'text/plain');
    });

    test('Ephemeral server transport mode', () async {
      handler(shelf.Request request) async {
        if (request.url.path == 'hello') {
          return shelf.Response.ok('Hello from real server!');
        }
        return shelf.Response.notFound('Not found');
      }

      client = TestClient(ShelfRequestHandler(handler),
          mode: TransportMode.ephemeralServer);

      final response = await client.get('/hello');

      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello from real server!');
    });
  });
}
