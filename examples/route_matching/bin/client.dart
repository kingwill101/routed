import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  Future<void> testRoute(String path, {Map<String, String>? headers}) async {
    try {
      print('\nTesting GET $path:');
      final response = await client.get(
        Uri.parse('$baseUrl$path'),
        headers: headers,
      );
      print('Status: ${response.statusCode}');
      print('Response: ${jsonDecode(response.body)}');
    } catch (e) {
      print('Error: $e');
    }
  }

  try {
    // Test basic route
    await testRoute('/hello');

    // Test parameter route
    await testRoute('/users/123');

    // Test optional parameter
    await testRoute('/posts');
    await testRoute('/posts/2');

    // Test type constraint
    await testRoute('/items/123');
    await testRoute('/items/abc'); // Should fail

    // Test multiple parameters
    await testRoute('/users/123/posts/456');

    // Test regex constraint
    await testRoute('/products/AB123');
    await testRoute('/products/123'); // Should fail

    // Test domain constraint
    await testRoute('/admin', headers: {'Host': 'admin.localhost'});
    await testRoute('/admin'); // Should fail

    // Test wildcard
    await testRoute('/files/path/to/something.txt');

    // Test group routes
    await testRoute('/api/v1/status');
    await testRoute('/api/v1/admin/dashboard');

    // Test fallback
    await testRoute('/non-existent-route');
  } finally {
    client.close();
  }
}
