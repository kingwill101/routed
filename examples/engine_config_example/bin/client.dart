import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test trailing slash redirect
  var response = await http.get(Uri.parse('$baseUrl/users/'));
  print('Trailing Slash Redirect:');
  print('Status: ${response.statusCode}');
  print('Location Header: ${response.headers['location']}\n');

  // Test method not allowed
  response = await http.put(Uri.parse('$baseUrl/users'));
  print('Method Not Allowed:');
  print('Status: ${response.statusCode}');
  print('Allow Header: ${response.headers['allow']}\n');

  // Test IP forwarding with X-Real-IP
  response = await http.get(
    Uri.parse('$baseUrl/ip'),
    headers: {'X-Real-IP': '1.2.3.4'},
  );
  print('IP Forwarding (X-Real-IP):');
  print('Body: ${response.body}\n');

  // Test IP forwarding with X-Forwarded-For
  response = await http.get(
    Uri.parse('$baseUrl/ip'),
    headers: {'X-Forwarded-For': '5.6.7.8'},
  );
  print('IP Forwarding (X-Forwarded-For):');
  print('Body: ${response.body}');
}
