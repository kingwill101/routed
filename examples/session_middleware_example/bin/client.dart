import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';
  final client = http.Client();

  try {
    // Set session data
    var response = await client.post(
      Uri.parse('$baseUrl/session'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': 'testuser',
        'preferences': {'theme': 'dark', 'language': 'en'}
      }),
    );
    print('Set Session Data:');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
    print('Set-Cookie: ${response.headers['set-cookie']}\n');

    // Get session data using the cookie from the previous response
    final cookie = response.headers['set-cookie'];
    response = await client.get(
      Uri.parse('$baseUrl/session'),
      headers: {'Cookie': cookie ?? ''},
    );
    print('Get Session Data:');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } finally {
    client.close();
  }
}
