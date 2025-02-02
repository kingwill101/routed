import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test accessing static files
  print('\nTesting static file access:');
  var response = await http.get(Uri.parse('$baseUrl/public/index.html'));
  print('HTML file:');
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  response = await http.get(Uri.parse('$baseUrl/public/styles.css'));
  print('CSS file:');
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  // Test directory listing
  print('Testing directory listing:');
  response = await http.get(Uri.parse('$baseUrl/files'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  // Test single file serving
  print('Testing single file serving:');
  response = await http.get(Uri.parse('$baseUrl/logo'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}');
}
