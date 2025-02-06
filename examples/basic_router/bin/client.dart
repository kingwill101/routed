import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test basic GET route
  print('\nTesting basic GET:');
  var response = await http.get(Uri.parse('$baseUrl/hello'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test route with path parameter
  print('\nTesting path parameter:');
  response = await http.get(Uri.parse('$baseUrl/users/123'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test POST route
  print('\nTesting POST:');
  response = await http.post(
    Uri.parse('$baseUrl/users'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'name': 'John', 'age': 30}),
  );
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test query parameters
  print('\nTesting query parameters:');
  response = await http.get(
    Uri.parse('$baseUrl/search?q=test&page=2'),
  );
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test grouped routes
  print('\nTesting grouped routes:');
  response = await http.get(Uri.parse('$baseUrl/api/status'));
  print('Status route:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  response = await http.post(
    Uri.parse('$baseUrl/api/data'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'test': 'data'}),
  );
  print('\nData route:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
