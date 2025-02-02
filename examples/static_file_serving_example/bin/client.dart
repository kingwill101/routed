import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test directory listing
  var response = await http.get(Uri.parse('$baseUrl/static'));
  print('Directory Listing:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test static file access
  response = await http.get(Uri.parse('$baseUrl/static/test_file.txt'));
  print('Static File Access:');
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  // Test nested file access
  response =
      await http.get(Uri.parse('$baseUrl/static/nested/nested_file.txt'));
  print('Nested File Access:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test direct file route
  response = await http.get(Uri.parse('$baseUrl/file'));
  print('Direct File Route:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}\n');

  // Test non-existent file
  response = await http.get(Uri.parse('$baseUrl/static/nonexistent.txt'));
  print('Non-existent File:');
  print('Status: ${response.statusCode}\n');

  // Test path traversal attempt
  response = await http.get(Uri.parse('$baseUrl/static/../outside.txt'));
  print('Path Traversal Attempt:');
  print('Status: ${response.statusCode}');
}
