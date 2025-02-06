import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test public route
    print('\nTesting GET /public:');
    var response = await client.get(Uri.parse('$baseUrl/public'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test rate-limited route
    print('\nTesting GET /api/status (multiple requests):');
    for (var i = 0; i < 12; i++) {
      response = await client.get(Uri.parse('$baseUrl/api/status'));
      print('Request $i - Status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print(jsonDecode(response.body));
        break;
      }
    }

    // Test protected route without auth
    print('\nTesting GET /admin/dashboard (no auth):');
    response = await client.get(Uri.parse('$baseUrl/admin/dashboard'));
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test protected route with auth
    print('\nTesting GET /admin/dashboard (with auth):');
    response = await client.get(
      Uri.parse('$baseUrl/admin/dashboard'),
      headers: {'Authorization': 'secret-token'},
    );
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test protected POST route
    print('\nTesting POST /admin/update:');
    response = await client.post(
      Uri.parse('$baseUrl/admin/update'),
      headers: {
        'Authorization': 'secret-token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'data': 'test update'}),
    );
    print('Status: ${response.statusCode}');
    print(jsonDecode(response.body));

    // Test error route
    print('\nTesting GET /error:');
    response = await client.get(Uri.parse('$baseUrl/error'));
    print('Status: ${response.statusCode}');
    print(response.body);
  } finally {
    client.close();
  }
}
