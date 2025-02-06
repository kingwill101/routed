import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test validation error
    print('\nTesting GET /validation-error:');
    var response = await client.get(Uri.parse('$baseUrl/validation-error'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test engine error
    print('\nTesting GET /engine-error:');
    response = await client.get(Uri.parse('$baseUrl/engine-error'));
    print('Status: ${response.statusCode}');
    print(response.body);

    // Test custom error
    print('\nTesting GET /custom-error:');
    response = await client.get(Uri.parse('$baseUrl/custom-error'));
    print('Status: ${response.statusCode}');
    print(response.body);

    // Test uncaught error
    print('\nTesting GET /uncaught-error:');
    response = await client.get(Uri.parse('$baseUrl/uncaught-error'));
    print('Status: ${response.statusCode}');
    print(response.body);

    // Test form validation - missing fields
    print('\nTesting POST /users (missing fields):');
    response = await client.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test form validation - valid data
    print('\nTesting POST /users (valid data):');
    response = await client.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body:
          jsonEncode({'email': 'test@example.com', 'password': 'password123'}),
    );
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));
  } finally {
    client.close();
  }
}
