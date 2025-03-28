import 'dart:convert';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<shelf.Response> shelfApp(shelf.Request request) async {
  final path = request.url.path;

  if (path == 'hello') {
    return shelf.Response.ok('Hello, World!');
  }

  if (path == 'json') {
    return shelf.Response.ok(
      jsonEncode({'message': 'Hello, JSON!'}),
      headers: {'content-type': 'application/json'},
    );
  }

  if (path == 'echo' && request.method == 'POST') {
    final body = await request.readAsString();
    return shelf.Response.ok(body);
  }

  if (path == 'headers') {
    return shelf.Response.ok('Headers test', headers: {
      'x-custom-header': 'test-value',
      'content-type': 'text/plain',
    });
  }

  if (path == 'status-code') {
    return shelf.Response(418, body: 'I\'m a teapot');
  }

  return shelf.Response.notFound('Not found');
}

void main() {
  final handler = ShelfRequestHandler(shelfApp);
  group('ShelfRequestHandler', () {
    serverTest(
      "Get text response",
      (client, h) async {
        final response = await client.get('/hello');
        response.assertStatus(200).assertBodyEquals('Hello, World!');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'GET JSON response',
      (client, h) async {
        final response = await client.get('/json');

        response.assertStatus(200).assertJsonPath('message', 'Hello, JSON!');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'POST echo request',
      (client, h) async {
        final response = await client.post('/echo', 'Echo this text');

        response.assertStatus(200).assertBodyEquals('Echo this text');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Headers are properly set',
      (client, h) async {
        final response = await client.get('/headers');

        response
            .assertStatus(200)
            .assertHeader('x-custom-header', 'test-value')
            .assertHeader('content-type', 'text/plain');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Status codes are properly set',
      (client, h) async {
        final response = await client.get('/status-code');

        response.assertStatus(418).assertBodyEquals('I\'m a teapot');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Not found returns 404',
      (client, h) async {
        final response = await client.get('/not-exists');

        response.assertStatus(404).assertBodyEquals('Not found');
      },
      handler: handler,
      transportMode: TransportMode.inMemory,
    );

    serverTest(
      'Works with ephemeral server',
      (client, h) async {
        final response = await client.get('/hello');

        response.assertStatus(200).assertBodyEquals('Hello, World!');
      },
      handler: handler,
      transportMode: TransportMode.ephemeralServer,
    );
  });
}
