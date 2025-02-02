import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test integer parameter
  print('\nTesting integer parameter:');
  var response = await http.get(Uri.parse('$baseUrl/users/123'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test double parameter
  print('\nTesting double parameter:');
  response = await http.get(Uri.parse('$baseUrl/products/19.99'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test slug parameter
  print('\nTesting slug parameter:');
  response = await http.get(Uri.parse('$baseUrl/posts/my-awesome-post'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test UUID parameter
  print('\nTesting UUID parameter:');
  response = await http.get(
      Uri.parse('$baseUrl/resources/123e4567-e89b-12d3-a456-426614174000'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test email parameter
  print('\nTesting email parameter:');
  response =
      await http.get(Uri.parse('$baseUrl/users/by-email/test@example.com'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test IP parameter
  print('\nTesting IP parameter:');
  response = await http.get(Uri.parse('$baseUrl/clients/192.168.1.1'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test optional parameter
  print('\nTesting optional parameter:');
  response = await http.get(Uri.parse('$baseUrl/articles/tech'));
  print('With only category:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/articles/tech/programming'));
  print('\nWith category and subcategory:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test wildcard parameter
  print('\nTesting wildcard parameter:');
  response = await http.get(Uri.parse('$baseUrl/files/2023/images/photo.jpg'));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
