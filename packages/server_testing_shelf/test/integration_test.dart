import 'dart:convert';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as router;

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Shelf Router Integration Tests', () {
    test('Works with shelf_router', () async {
      // Create a shelf app using shelf_router
      final app = router.Router();
      
      // Add routes
      app.get('/hello', (shelf.Request request) {
        return shelf.Response.ok('Hello, Router!');
      });
      
      app.get('/users/<id>', (shelf.Request request, String id) {
        final userData = {
          '1': {'id': 1, 'name': 'Alice'},
          '2': {'id': 2, 'name': 'Bob'},
          '3': {'id': 3, 'name': 'Charlie'},
        };
        
        if (userData.containsKey(id)) {
          return shelf.Response.ok(
            jsonEncode(userData[id]),
            headers: {'content-type': 'application/json'},
          );
        }
        
        return shelf.Response.notFound('User not found');
      });
      
      app.post('/users', (shelf.Request request) async {
        final data = jsonDecode(await request.readAsString());
        // Simulate creating a user with an ID
        final newUser = {
          'id': 4,
          'name': data['name'],
          'createdAt': DateTime.now().toIso8601String(),
        };
        
        return shelf.Response(201,
          body: jsonEncode(newUser),
          headers: {'content-type': 'application/json'},
        );
      });
      
      // Setup with server_testing
      client = TestClient(ShelfRequestHandler(app));

      // Test GET request
      var response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello, Router!');
        
      // Test GET with route parameter
      response = await client.getJson('/users/1');
      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
            .has('id')
            .where('id', 1)
            .has('name')
            .where('name', 'Alice');
        });
        
      // Test 404 for non-existent user
      response = await client.getJson('/users/99');
      response.assertStatus(404);
        
      // Test POST request
      response = await client.postJson('/users', {'name': 'Dave'});
      response
        ..assertStatus(201)
        ..assertJson((json) {
          json
            .has('id')
            .where('id', 4)
            .has('name')
            .where('name', 'Dave')
            .has('createdAt');
        });
    });
    
    test('Works with shelf middleware', () async {
      // Create middleware for authentication
      final authMiddleware = (shelf.Handler innerHandler) {
        return (shelf.Request request) {
          final authHeader = request.headers['authorization'];
          if (authHeader != 'Bearer test-token') {
            return shelf.Response(401, body: 'Unauthorized');
          }
          return innerHandler(request);
        };
      };
      
      // Create middleware for logging
      final loggingMiddleware = (shelf.Handler innerHandler) {
        return (shelf.Request request) async {
          // In a real app, you would log the request here
          final response = await innerHandler(request);
          // Add a header to the response to show the middleware ran
          return response.change(
            headers: {'X-Logged': 'true'},
          );
        };
      };
      
      // Create a simple handler
      final handler = (shelf.Request request) {
        return shelf.Response.ok('Protected resource');
      };
      
      // Apply middleware
      final app = shelf.Pipeline()
          .addMiddleware(loggingMiddleware)
          .addMiddleware(authMiddleware)
          .addHandler(handler);
      
      // Setup with server_testing
      client = TestClient(ShelfRequestHandler(app));
      
      // Test unauthorized request
      var response = await client.get('/');
      response
        ..assertStatus(401)
        ..assertBodyEquals('Unauthorized');
        
      // Test authorized request
      response = await client.get('/', headers: {
        'Authorization': ['Bearer test-token']
      });
      response
        ..assertStatus(200)
        ..assertBodyEquals('Protected resource')
        ..assertHeader('X-Logged', 'true');
    });
    
    test('Works with request context', () async {
      // Handler that uses context
      final handler = (shelf.Request request) {
        // Get the request with added context data
        final requestWithContext = request.change(context: {
          'user': {'id': 1, 'name': 'Test User'},
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        // Handler that uses the context
        return (shelf.Request req) {
          final context = req.context;
          return shelf.Response.ok(
            jsonEncode(context),
            headers: {'content-type': 'application/json'},
          );
        }(requestWithContext);
      };
      
      // Setup with server_testing
      client = TestClient(ShelfRequestHandler(handler));
      
      // Test context data in response
      final response = await client.get('/');
      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
            .has('user')
            .where('user.id', 1)
            .where('user.name', 'Test User')
            .has('timestamp');
        });
    });
  });
}