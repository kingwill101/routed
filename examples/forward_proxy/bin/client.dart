import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test proxy status
    print('\n[Client] Testing GET /status:');
    var response = await client.get(Uri.parse('$baseUrl/status'));
    print('[Client] Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test proxied request
    print('\n[Client] Testing GET /headers:');
    response = await client.get(
      Uri.parse('$baseUrl/headers'),
      headers: {'X-Test-Header': 'test-value'},
    );
    print('[Client] Status: ${response.statusCode}');
    print('Headers:');
    response.headers.forEach((key, value) {
      print('  $key: $value');
    });
    print('Body: ${response.body}');

    // Test invalid target
    print('\n[Client] Testing GET /hello:');
    response = await client.get(Uri.parse('$baseUrl/hello'));
    print('[Client] Status: ${response.statusCode}');
    print(jsonDecode(response.body));
  } finally {
    client.close();
  }
}
