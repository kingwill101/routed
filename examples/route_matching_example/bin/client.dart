import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test different HTTP methods
  final methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'HEAD',
    'OPTIONS',
    'DELETE',
  ];

  for (final method in methods) {
    var request = http.Request(method, Uri.parse('$baseUrl/test'));
    var response = await request.send();
    var body = await response.stream.bytesToString();
    print('$method /test:');
    print('Status: ${response.statusCode}');
    print('Body: $body\n');
  }

  // Test path parameters
  var response = await http.get(
    Uri.parse('$baseUrl/test/john/doe/path/to/resource'),
  );
  print('Path Parameters:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
