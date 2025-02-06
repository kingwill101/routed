import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000';
  final client = http.Client();

  try {
    // Test basic template
    print('\nTesting GET /hello:');
    var response = await client.get(Uri.parse('$baseUrl/hello'));
    print('Status: ${response.statusCode}');
    print('Body length: ${response.body.length} bytes');
    print('Content snippet:');
    print(response.body.substring(0, response.body.length.clamp(0, 200)));

    // Test extended template
    print('\nTesting GET /extended:');
    response = await client.get(Uri.parse('$baseUrl/extended'));
    print('Status: ${response.statusCode}');
    print('Body length: ${response.body.length} bytes');
    print('Content snippet:');
    print(response.body.substring(0, response.body.length.clamp(0, 200)));

    // Test dynamic data
    print('\nTesting GET /data/TestUser:');
    response = await client.get(Uri.parse('$baseUrl/data/TestUser'));
    print('Status: ${response.statusCode}');
    print('Body length: ${response.body.length} bytes');
    print('Content snippet:');
    print(response.body.substring(0, response.body.length.clamp(0, 200)));
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
