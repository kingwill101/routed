import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test custom error
  print('\nTesting custom error:');
  var response = await http.get(Uri.parse('$baseUrl/custom-error'));
  print('Custom Error Response:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test standard error
  print('\nTesting standard error:');
  response = await http.get(Uri.parse('$baseUrl/standard-error'));
  print('Standard Error Response:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test validation error (invalid data)
  print('\nTesting validation error:');
  response = await http.post(
    Uri.parse('$baseUrl/validate'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'email': 'invalid-email',
      'age': 'not-a-number',
    }),
  );
  print('Validation Error Response:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test validation success
  print('\nTesting validation success:');
  response = await http.post(
    Uri.parse('$baseUrl/validate'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'email': 'test@example.com',
      'age': '25',
    }),
  );
  print('Validation Success Response:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
