import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test Liquid template
  print('\nTesting Liquid template:');
  var response = await http.get(Uri.parse('$baseUrl/liquid'));
  print('Status: ${response.statusCode}');
  print('Content-Type: ${response.headers['content-type']}');
  print('Body: ${response.body}');
}
