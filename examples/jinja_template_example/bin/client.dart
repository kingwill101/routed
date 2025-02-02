import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test basic template
  print('\nTesting basic template:');
  var response = await http.get(Uri.parse('$baseUrl/hello'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}\n');

  // Test template inheritance
  print('\nTesting template inheritance:');
  response = await http.get(Uri.parse('$baseUrl/extended'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}');
}
