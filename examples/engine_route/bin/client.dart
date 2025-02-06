import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test basic route
    print('\nTesting GET /hello:');
    var response = await client.get(Uri.parse('$baseUrl/hello'));
    print(response.body);

    // Test route with parameter
    print('\nTesting GET /users/123:');
    response = await client.get(Uri.parse('$baseUrl/users/123'));
    print(jsonDecode(response.body));

    // Test typed parameter
    print('\nTesting GET /items/456:');
    response = await client.get(Uri.parse('$baseUrl/items/456'));
    print(jsonDecode(response.body));

    // Test optional parameter (default)
    print('\nTesting GET /posts:');
    response = await client.get(Uri.parse('$baseUrl/posts'));
    print(jsonDecode(response.body));

    // Test optional parameter (provided)
    print('\nTesting GET /posts/2:');
    response = await client.get(Uri.parse('$baseUrl/posts/2'));
    print(jsonDecode(response.body));

    // Test wildcard parameter
    print('\nTesting GET /files/path/to/file.txt:');
    response = await client.get(Uri.parse('$baseUrl/files/path/to/file.txt'));
    print(jsonDecode(response.body));

    // Test constraint match
    print('\nTesting GET /products/123:');
    response = await client.get(Uri.parse('$baseUrl/products/123'));
    print(jsonDecode(response.body));

    // Test constraint fail
    print('\nTesting GET /products/12 (should fail):');
    response = await client.get(Uri.parse('$baseUrl/products/12'));
    print(jsonDecode(response.body));

    // Test fallback route
    print('\nTesting GET /non-existent:');
    response = await client.get(Uri.parse('$baseUrl/non-existent'));
    print(jsonDecode(response.body));
  } finally {
    client.close();
  }
}
