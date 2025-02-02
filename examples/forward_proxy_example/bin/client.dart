import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test GET request through proxy
  print('\nTesting GET request:');
  try {
    var response = await http.get(Uri.parse(baseUrl));
    print('Status: ${response.statusCode}');
    print('Headers:');
    response.headers.forEach((key, value) {
      print('  $key: $value');
    });
    print('Body length: ${response.body.length} bytes');
  } catch (e) {
    print('Error: $e');
  }

  // Test POST request through proxy
  print('\nTesting POST request:');
  try {
    var response = await http.post(
      Uri.parse('$baseUrl/api/test'),
      body: {'test': 'data'},
    );
    print('Status: ${response.statusCode}');
    print('Headers:');
    response.headers.forEach((key, value) {
      print('  $key: $value');
    });
    print('Body length: ${response.body.length} bytes');
  } catch (e) {
    print('Error: $e');
  }

  // Test request to non-existent path
  print('\nTesting non-existent path:');
  try {
    var response = await http.get(
      Uri.parse('$baseUrl/this/path/does/not/exist'),
    );
    print('Status: ${response.statusCode}');
    print('Body length: ${response.body.length} bytes');
  } catch (e) {
    print('Error: $e');
  }
}
