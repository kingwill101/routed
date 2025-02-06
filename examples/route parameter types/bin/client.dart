import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  Future<void> testRoute(String path, {String? label}) async {
    try {
      print('\nTesting ${label ?? path}:');
      final response = await client.get(Uri.parse('$baseUrl$path'));
      print('Status: ${response.statusCode}');
      print('Response: ${_formatJson(response.body)}');
    } catch (e) {
      print('Error: $e');
    }
  }

  try {
    // Test built-in parameter types
    await testRoute('/items/123', label: 'Integer parameter');
    await testRoute('/prices/99.99', label: 'Double parameter');
    await testRoute('/users/123e4567-e89b-12d3-a456-426614174000',
        label: 'UUID parameter');
    await testRoute('/posts/my-blog-post', label: 'Slug parameter');
    await testRoute('/mail/user@example.com', label: 'Email parameter');
    await testRoute('/links/https://example.com', label: 'URL parameter');
    await testRoute('/address/192.168.1.1', label: 'IP parameter');

    // Test multiple parameters
    await testRoute('/orders/123/items/SKU123/price/49.99',
        label: 'Multiple parameters');

    // Test custom type pattern
    await testRoute('/contact/123-456-7890', label: 'Custom phone pattern');

    // Test global parameter pattern
    await testRoute('/products/AB1234', label: 'Global parameter pattern');

    // Test invalid values
    await testRoute('/items/abc', label: 'Invalid integer');
    await testRoute('/posts/INVALID-SLUG!', label: 'Invalid slug');
    await testRoute('/mail/invalid-email', label: 'Invalid email');
  } finally {
    client.close();
  }
}

String _formatJson(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(decoded);
  } catch (_) {
    return jsonStr;
  }
}
