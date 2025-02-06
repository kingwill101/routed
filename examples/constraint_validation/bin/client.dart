import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test numeric constraint
  print('\nTesting numeric constraint:');
  var response = await http.get(Uri.parse('$baseUrl/items/123'));
  print('Valid numeric ID:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/items/abc'));
  print('\nInvalid numeric ID:');
  print('Status: ${response.statusCode}');

  // Test multiple constraints
  print('\nTesting multiple constraints:');
  response = await http.get(Uri.parse('$baseUrl/users/42/my-post'));
  print('Valid userId and slug:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/users/abc/MY-POST'));
  print('\nInvalid userId and slug:');
  print('Status: ${response.statusCode}');

  // Test custom pattern constraint
  print('\nTesting custom pattern constraint:');
  response = await http.get(Uri.parse('$baseUrl/products/AB1234'));
  print('Valid SKU:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  response = await http.get(Uri.parse('$baseUrl/products/12ABCD'));
  print('\nInvalid SKU:');
  print('Status: ${response.statusCode}');
}
