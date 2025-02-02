import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test route with all middleware levels
  var response = await http.get(Uri.parse('$baseUrl/test'));
  print('Route with middlewares:');
  print('Status: ${response.statusCode}');
  print('Headers:');
  print('  X-Engine-Middleware: ${response.headers['x-engine-middleware']}');
  print('  X-Router-Middleware: ${response.headers['x-router-middleware']}');
  print('  X-Route-Middleware: ${response.headers['x-route-middleware']}');
  print('Body: ${response.body}\n');

  // Test group route with group middleware
  response = await http.get(Uri.parse('$baseUrl/admin/dashboard'));
  print('Group route with middlewares:');
  print('Status: ${response.statusCode}');
  print('Headers:');
  print('  X-Engine-Middleware: ${response.headers['x-engine-middleware']}');
  print('  X-Router-Middleware: ${response.headers['x-router-middleware']}');
  print('  X-Group-Middleware: ${response.headers['x-group-middleware']}');
  print('Body: ${response.body}');
}
