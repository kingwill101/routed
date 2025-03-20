import 'dart:convert';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  group('ShelfRequestHandler', () {
    late shelf.Handler shelfApp;

    setUp(() {
      // Create a simple Shelf application
      shelfApp = (request) async {
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
      };
    });

    test('GET text response', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler, mode: TransportMode.inMemory);
      
      final response = await client.get('/hello');
      
      response
        .assertStatus(200)
        .assertBodyEquals('Hello, World!');
        
      await client.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('GET JSON response', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler);
      
      final response = await client.get('/json');
      
      response
        .assertStatus(200)
        .assertJsonPath('message', 'Hello, JSON!');
        
      await client.close();
    });

    test('POST echo request', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler);
      
      final response = await client.post('/echo', 'Echo this text');
      
      response
        .assertStatus(200)
        .assertBodyEquals('Echo this text');
        
      await client.close();
    });

    test('Headers are properly set', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler);
      
      final response = await client.get('/headers');
      
      response
        .assertStatus(200)
        .assertHeader('x-custom-header', 'test-value')
        .assertHeader('content-type', 'text/plain');
        
      await client.close();
    });

    test('Status codes are properly set', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler);
      
      final response = await client.get('/status-code');
      
      response
        .assertStatus(418)
        .assertBodyEquals('I\'m a teapot');
        
      await client.close();
    });

    test('Not found returns 404', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(handler);
      
      final response = await client.get('/not-exists');
      
      response
        .assertStatus(404)
        .assertBodyEquals('Not found');
        
      await client.close();
    });

    // This test actually uses a real HTTP server (ephemeral transport)
    test('Works with ephemeral server', () async {
      final handler = ShelfRequestHandler(shelfApp);
      final client = TestClient(
        handler, 
        mode: TransportMode.ephemeralServer
      );
      
      final response = await client.get('/hello');
      
      response
        .assertStatus(200)
        .assertBodyEquals('Hello, World!');
        
      await client.close();
    });
  });
}