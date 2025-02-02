import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test users endpoints
  print('\nTesting Users API:');
  var response = await http.get(Uri.parse('$baseUrl/v1/users'));
  print('List Users:');
  print('Status: ${response.statusCode}');
  print('API Version: ${response.headers['api-version']}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/v1/users/123'));
  print('\nGet User:');
  print('Status: ${response.statusCode}');
  print('API Version: ${response.headers['api-version']}');
  print('Body: ${response.body}');

  // Test posts endpoints
  print('\nTesting Posts API:');
  response = await http.get(Uri.parse('$baseUrl/v1/posts'));
  print('List Posts:');
  print('Status: ${response.statusCode}');
  print('API Version: ${response.headers['api-version']}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/v1/posts/456'));
  print('\nGet Post:');
  print('Status: ${response.statusCode}');
  print('API Version: ${response.headers['api-version']}');
  print('Body: ${response.body}');
}
