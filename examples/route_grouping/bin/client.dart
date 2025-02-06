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
      if (response.statusCode != 404) {
        print('Response: ${_formatJson(response.body)}');
      } else {
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  try {
    // Test admin routes without auth
    await testRoute('/admin/dashboard');

    // Test admin routes with auth
    await testRoute('/admin/dashboard',
        headers: {'Authorization': 'admin-token'});
    await testRoute('/admin/users', headers: {'Authorization': 'admin-token'});

    // Test API versions
    await testRoute('/api/v1/status');
    await testRoute('/api/v2/status');

    // Test resource routes
    await testRoute('/posts');
    await testRoute('/posts/1');
    await testRoute('/posts/1/comments');
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
