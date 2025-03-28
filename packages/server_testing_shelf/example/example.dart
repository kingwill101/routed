import 'dart:convert';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main() async {
  // A sample Shelf API
  api(shelf.Request request) async {
    final path = request.url.path;

    if (path == 'users') {
      return shelf.Response.ok(
        jsonEncode({
          'users': [
            {'id': 1, 'name': 'Alice', 'role': 'admin'},
            {'id': 2, 'name': 'Bob', 'role': 'user'},
            {'id': 3, 'name': 'Charlie', 'role': 'user'},
          ]
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == 'users' && request.url.queryParameters.containsKey('id')) {
      final id = int.tryParse(request.url.queryParameters['id'] ?? '');
      if (id == 1) {
        return shelf.Response.ok(
          jsonEncode({'id': 1, 'name': 'Alice', 'role': 'admin'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return shelf.Response.notFound('User not found');
    }

    if (path == 'login' && request.method == 'POST') {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (data['username'] == 'admin' && data['password'] == 'password123') {
        return shelf.Response.ok(
          jsonEncode({'token': 'mock-jwt-token', 'success': true}),
          headers: {'content-type': 'application/json'},
        );
      }

      return shelf.Response(
        401,
        body: jsonEncode({'error': 'Invalid credentials', 'success': false}),
        headers: {'content-type': 'application/json'},
      );
    }

    return shelf.Response.notFound('Not found');
  }

  // Create the ShelfRequestHandler
  final handler = ShelfRequestHandler(const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(api));

  // Run tests using server_testing

  // Test 1: Get all users
  serverTest('GET /users returns list of users', (client, h) async {
    final response = await client.get('/users');

    response.assertStatus(200).assertJson((json) {
      json
          .has('users')
          .count('users', 3)
          .where('users.0.name', 'Alice')
          .where('users.0.role', 'admin');
    });
  }, handler: handler);

  // Test 2: Get a specific user
  serverTest('GET /users?id=1 returns specific user', (client, h) async {
    final response = await client.get('/users?id=1');

    response.assertStatus(200).assertJson((json) {
      json.where('name', 'Alice').where('role', 'admin');
    });
  }, handler: handler);

  // Test 3: Login with valid credentials
  serverTest('POST /login with valid credentials succeeds', (client, h) async {
    final response = await client
        .postJson('/login', {'username': 'admin', 'password': 'password123'});

    response.assertStatus(200).assertJson((json) {
      json.has('token').where('success', true);
    });
  }, handler: handler);

  // Test 4: Login with invalid credentials
  serverTest('POST /login with invalid credentials fails', (client, h) async {
    final response = await client
        .postJson('/login', {'username': 'wrong', 'password': 'wrong'});

    response.assertStatus(401).assertJson((json) {
      json.has('error').where('success', false);
    });
  }, handler: handler);

  // Test 5: Accessing non-existent endpoint
  serverTest('GET /not-exists returns 404', (client, h) async {
    final response = await client.get('/not-exists');

    response.assertStatus(404).assertBodyEquals('Not found');
  }, handler: handler);
}
