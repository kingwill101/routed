import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test Jinja template
  print('\nTesting Jinja template:');
  var response = await http.get(Uri.parse('$baseUrl/jinja'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  // Test Liquid template
  print('\nTesting Liquid template:');
  response = await http.get(Uri.parse('$baseUrl/liquid'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}');
}
