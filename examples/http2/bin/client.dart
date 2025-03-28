import 'dart:convert';

import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test existing route
    print('\nTesting GET /hello (existing route):');
    var response = await client.get(Uri.parse('$baseUrl/hello'));
    print('Status: ${response.statusCode}');
    print(response.body);

    // Test global fallback
    print('\nTesting GET /nonexistent (global fallback):');
    response = await client.get(Uri.parse('$baseUrl/nonexistent'));
    print('Status: ${response.statusCode}');
    print(response.body);

    // Test v1 API fallback
    print('\nTesting GET /api/v1/nonexistent (v1 fallback):');
    response = await client.get(Uri.parse('$baseUrl/api/v1/nonexistent'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test regular API route
    print('\nTesting GET /api/v1/users (existing API route):');
    response = await client.get(Uri.parse('$baseUrl/api/v1/users'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test secured route with middleware
    print('\nTesting GET /secured/test (with middleware):');
    response = await client.get(Uri.parse('$baseUrl/secured/test'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));
  } finally {
    client.close();
  }
}
