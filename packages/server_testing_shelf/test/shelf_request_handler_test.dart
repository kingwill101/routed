import 'dart:convert';

import 'package:http_parser/http_parser.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  group('ShelfRequestHandler Tests', () {
    final handler = ShelfRequestHandler((request) async {
      if (request.url.path == 'hello') {
        return shelf.Response.ok('Hello, World!');
      }
      if (request.url.path == 'json' && request.method == 'POST') {
        final payload = jsonDecode(await request.readAsString());
        return shelf.Response.ok(
          jsonEncode({'received': payload, 'success': true}),
          headers: {'content-type': 'application/json'},
        );
      }
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
      if (request.url.path == 'upload' && request.method == 'POST') {
        if (request.headers['content-type']
                ?.startsWith('multipart/form-data') ==
            true) {
          return shelf.Response.ok(
            jsonEncode({
              'success': true,
              'received': await request.readAsString(),
              'receivedMultipart': true,
              'contentTypeReceived': request.headers['content-type'],
              'contentLength': request.headers['content-length'],
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }
      if (request.url.path == 'search') {
        return shelf.Response.ok(
          jsonEncode(request.url.queryParameters),
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == 'custom') {
        return shelf.Response(418, body: 'Custom response', headers: {
          'X-Custom-Header': 'test-value',
          'Content-Type': 'text/plain'
        });
      }
      return shelf.Response.notFound('Not found');
    });

    serverTest(
      'Basic GET request',
      (client, h) async {
        final response = await client.get('/hello');
        response
          ..assertStatus(200)
          ..assertBodyEquals('Hello, World!');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'JSON request and response',
      (client, h) async {
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
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'URL-encoded form submission',
      (client, h) async {
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
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Multipart Form submission',
      (client, h) async {
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
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Query parameter handling',
      (client, h) async {
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
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Custom status codes and headers',
      (client, h) async {
        final response = await client.get('/custom');

        response
          ..assertStatus(418)
          ..assertBodyEquals('Custom response')
          ..assertHeader('X-Custom-Header', 'test-value')
          ..assertHeader('Content-Type', 'text/plain');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Ephemeral server transport mode',
      (client, h) async {
        final response = await client.get('/hello');

        response
          ..assertStatus(200)
          ..assertBodyEquals('Hello from real server!');
      },
      handler: ShelfRequestHandler((request) async {
        if (request.url.path == 'hello') {
          return shelf.Response.ok('Hello from real server!');
        }
        return shelf.Response.notFound('Not found');
      }),
      transportMode: TransportMode.ephemeralServer,
    );
  });
}
