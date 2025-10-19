import 'dart:convert';
import 'dart:io';

import 'package:server_testing/server_testing.dart';

void main() {
  group('IoRequestHandler', () {
    Future<void> simpleHandler(HttpRequest request) async {
      final response = request.response;
      response.statusCode = 200;
      response.write('Hello, World!');
      await response.close();
    }

    serverTest(
      'handles request with simple callback',
      (client, _) async {
        final response = await client.get('/');
        response.assertStatus(200).assertBodyEquals('Hello, World!');
      },
      handler: IoRequestHandler(simpleHandler),
    );

    Future<void> jsonHandler(HttpRequest request) async {
      final response = request.response;
      response.statusCode = 200;
      response.headers.contentType = ContentType.json;
      response.write('{"message": "success"}');
      await response.close();
    }

    serverTest('handles JSON responses', (client, _) async {
      final response = await client.getJson('/');
      response
          .assertStatus(200)
          .assertJson(
            (json) => json.has('message').where('message', 'success'),
          );
    }, handler: IoRequestHandler(jsonHandler));

    Future<void> routingHandler(HttpRequest request) async {
      final response = request.response;

      if (request.uri.path == '/ping') {
        response.statusCode = 200;
        response.write('pong');
      } else if (request.uri.path == '/health') {
        response.statusCode = 200;
        response.headers.contentType = ContentType.json;
        response.write('{"status": "healthy"}');
      } else {
        response.statusCode = 404;
        response.write('Not found');
      }

      await response.close();
    }

    final routingHandlerInstance = IoRequestHandler(routingHandler);

    serverTest('handles /ping route', (client, _) async {
      final response = await client.get('/ping');
      response.assertStatus(200).assertBodyEquals('pong');
    }, handler: routingHandlerInstance);

    serverTest('handles /health route', (client, _) async {
      final response = await client.getJson('/health');
      response.assertStatus(200).assertJsonPath('status', 'healthy');
    }, handler: routingHandlerInstance);

    serverTest('handles unknown route with 404', (client, _) async {
      final response = await client.get('/unknown');
      response.assertStatus(404).assertBodyEquals('Not found');
    }, handler: routingHandlerInstance);

    Future<void> ephemeralHandler(HttpRequest request) async {
      final response = request.response;
      response.statusCode = 200;
      response.write('Server mode');
      await response.close();
    }

    serverTest(
      'works with ephemeral server transport',
      (client, _) async {
        final response = await client.get('/');
        response.assertStatus(200).assertBodyEquals('Server mode');
      },
      handler: IoRequestHandler(ephemeralHandler),
      transportMode: TransportMode.ephemeralServer,
    );

    Future<void> echoHandler(HttpRequest request) async {
      final response = request.response;

      if (request.method == 'POST' && request.uri.path == '/echo') {
        final body = await utf8.decodeStream(request);
        response.statusCode = 200;
        response.write('Echo: $body');
      } else {
        response.statusCode = 404;
        response.write('Not found');
      }

      await response.close();
    }

    serverTest('handles POST requests with body', (client, _) async {
      final response = await client.post('/echo', 'test data');
      response.assertStatus(200).assertBodyEquals('Echo: test data');
    }, handler: IoRequestHandler(echoHandler));

    void syncHandler(HttpRequest request) {
      final response = request.response;
      response.statusCode = 200;
      response.write('Sync response');
      response.close();
    }

    serverTest('handles synchronous callback', (client, _) async {
      final response = await client.get('/');
      response.assertStatus(200).assertBodyEquals('Sync response');
    }, handler: IoRequestHandler(syncHandler));

    Future<void> headerHandler(HttpRequest request) async {
      final response = request.response;
      response.statusCode = 200;
      response.headers.set('X-Custom-Header', 'custom-value');
      response.headers.contentType = ContentType.text;
      response.write('With headers');
      await response.close();
    }

    serverTest('handles custom headers', (client, _) async {
      final response = await client.get('/');
      response
          .assertStatus(200)
          .assertHeader('X-Custom-Header', 'custom-value')
          .assertBodyContains('With headers');
    }, handler: IoRequestHandler(headerHandler));

    test('can be used with TestClient directly', () async {
      Future<void> directHandler(HttpRequest request) async {
        final response = request.response;
        response.statusCode = 200;
        response.write('Direct client');
        await response.close();
      }

      final handler = IoRequestHandler(directHandler);
      final client = TestClient.inMemory(handler);

      final response = await client.get('/');
      response.assertStatus(200).assertBodyEquals('Direct client');

      await client.close();
    });
  });
}
