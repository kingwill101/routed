import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test JSON validation (success)
  var response = await http.post(
    Uri.parse('$baseUrl/json'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': 'test',
      'age': 25,
      'tags': ['one', 'two']
    }),
  );
  print('JSON Validation (success):');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test Form validation (success)
  response = await http.post(
    Uri.parse('$baseUrl/form'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'name=test&age=25',
  );
  print('Form Validation (success):');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test Query validation (success)
  response = await http.get(
    Uri.parse('$baseUrl/search?q=test&page=1&sort=desc'),
  );
  print('Query Validation (success):');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test validation error handling (failure)
  response = await http.post(
    Uri.parse('$baseUrl/validate'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': 'test',
      'age': 'invalid',
      'email': 'not-an-email',
      'tags': 'not-an-array'
    }),
  );
  print('Validation Error Handling (failure):');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
