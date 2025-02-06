import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test basic cache operations
    print('\nTesting basic cache operations:');
    var response = await client.get(Uri.parse('$baseUrl/cached-value'));
    print('First request (uncached): ${jsonDecode(response.body)}');

    response = await client.get(Uri.parse('$baseUrl/cached-value'));
    print('Second request (cached): ${jsonDecode(response.body)}');

    // Test counter operations
    print('\nTesting counter operations:');
    response = await client.get(Uri.parse('$baseUrl/counter'));
    print(
        'Counter value after increment and decrement: ${jsonDecode(response.body)}');

    // Test remember cache
    print('\nTesting remember cache:');
    response = await client.get(Uri.parse('$baseUrl/remember'));
    print('Remembered value: ${jsonDecode(response.body)}');
  } finally {
    client.close();
  }
}
