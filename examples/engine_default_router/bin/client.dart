import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test GET /users
    print('\nTesting GET /users:');
    var response = await client.get(Uri.parse('$baseUrl/users'));
    print(jsonDecode(response.body));

    // Test POST /users
    print('\nTesting POST /users:');
    response = await client.post(
      Uri.parse('$baseUrl/users'),
      body: jsonEncode({'name': 'New User'}),
      headers: {'Content-Type': 'application/json'},
    );
    print(jsonDecode(response.body));

    // Test GET /users/{id}
    print('\nTesting GET /users/123:');
    response = await client.get(Uri.parse('$baseUrl/users/123'));
    print(jsonDecode(response.body));

    // Test GET /admin/stats without auth
    print('\nTesting GET /admin/stats without auth:');
    response = await client.get(Uri.parse('$baseUrl/admin/stats'));
    print(jsonDecode(response.body));

    // Test GET /admin/stats with auth
    print('\nTesting GET /admin/stats with auth:');
    response = await client.get(
      Uri.parse('$baseUrl/admin/stats'),
      headers: {'Authorization': 'secret'},
    );
    print(jsonDecode(response.body));

    // Test GET /articles/{slug}
    print('\nTesting GET /articles/hello-world:');
    response = await client.get(Uri.parse('$baseUrl/articles/hello-world'));
    print(jsonDecode(response.body));
  } finally {
    client.close();
  }
}
