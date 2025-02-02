import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test integer parameter
  var response = await http.get(Uri.parse('$baseUrl/users/123'));
  print('Integer Parameter:');
  print('Response: ${response.body}\n');

  // Test double parameter
  response = await http.get(Uri.parse('$baseUrl/price/12.34'));
  print('Double Parameter:');
  print('Response: ${response.body}\n');

  // Test slug parameter
  response = await http.get(Uri.parse('$baseUrl/posts/my-awesome-post'));
  print('Slug Parameter:');
  print('Response: ${response.body}\n');

  // Test UUID parameter
  response = await http.get(
    Uri.parse('$baseUrl/resources/123e4567-e89b-12d3-a456-426614174000'),
  );
  print('UUID Parameter:');
  print('Response: ${response.body}\n');

  // Test email parameter
  response = await http.get(
    Uri.parse('$baseUrl/subscribe/test.user@example.com'),
  );
  print('Email Parameter:');
  print('Response: ${response.body}\n');

  // Test IP parameter
  response = await http.get(Uri.parse('$baseUrl/diagnose/192.168.1.100'));
  print('IP Parameter:');
  print('Response: ${response.body}\n');

  // Test string parameter
  response = await http.get(Uri.parse('$baseUrl/anything/hello_world'));
  print('String Parameter:');
  print('Response: ${response.body}\n');

  // Test optional parameter
  response = await http.get(Uri.parse('$baseUrl/users/123/posts'));
  print('Optional Parameter (omitted):');
  print('Response: ${response.body}\n');

  response = await http.get(Uri.parse('$baseUrl/users/123/posts/my-post'));
  print('Optional Parameter (provided):');
  print('Response: ${response.body}\n');

  // Test wildcard parameter
  response = await http.get(
    Uri.parse('$baseUrl/files/2023/documents/report.pdf'),
  );
  print('Wildcard Parameter:');
  print('Response: ${response.body}');
}
