import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test GET /hello
  var response = await http.get(Uri.parse('$baseUrl/hello'));
  print('GET /hello:');
  print('Body: ${response.body}\n');

  // Test POST /echo
  response = await http.post(
    Uri.parse('$baseUrl/echo'),
    body: 'Test Body',
  );
  print('POST /echo:');
  print('Body: ${response.body}\n');

  // Test middleware
  response = await http.get(Uri.parse('$baseUrl/middleware'));
  print('GET /middleware:');
  print('Body: ${response.body}');
  print('Headers: ${response.headers}\n');

  // Test route groups
  response = await http.get(Uri.parse('$baseUrl/users'));
  print('GET /users:');
  print('Body: ${response.body}\n');

  response = await http.get(Uri.parse('$baseUrl/users/123'));
  print('GET /users/123:');
  print('Body: ${response.body}\n');

  response = await http.put(Uri.parse('$baseUrl/users/123'));
  print('PUT /users/123:');
  print('Body: ${response.body}');
}
