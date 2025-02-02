import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test fast route (should succeed)
  print('\nTesting fast route:');
  try {
    var response = await http.get(Uri.parse('$baseUrl/fast'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }

  // Test slow route (should timeout)
  print('\nTesting slow route:');
  try {
    var response = await http.get(Uri.parse('$baseUrl/slow'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }

  // Test API route within timeout
  print('\nTesting API route within timeout:');
  try {
    var response = await http.get(Uri.parse('$baseUrl/api/data'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }

  // Test API route that exceeds timeout
  print('\nTesting API route that exceeds timeout:');
  try {
    var response = await http.get(Uri.parse('$baseUrl/api/timeout'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
