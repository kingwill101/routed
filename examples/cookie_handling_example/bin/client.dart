import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';
  final client = http.Client();
  Map<String, String> cookies = {};

  // Helper function to update cookies from response
  void updateCookies(http.Response response) {
    final setCookies = response.headers['set-cookie'];
    if (setCookies != null) {
      for (var setCookie in setCookies.split(',')) {
        final cookie = setCookie.split(';')[0];
        final parts = cookie.split('=');
        if (parts.length == 2) {
          cookies[parts[0].trim()] = parts[1].trim();
        }
      }
    }
  }

  try {
    // Test setting a single cookie
    print('\nSetting single cookie:');
    var response = await client.get(Uri.parse('$baseUrl/set-cookie'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
    print('Set-Cookie Header: ${response.headers['set-cookie']}');
    updateCookies(response);

    // Test setting multiple cookies
    print('\nSetting preferences cookies:');
    response = await client.get(Uri.parse('$baseUrl/set-preferences'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
    print('Set-Cookie Header: ${response.headers['set-cookie']}');
    updateCookies(response);

    // Test reading cookies
    print('\nReading cookies:');
    response = await client.get(
      Uri.parse('$baseUrl/get-cookies'),
      headers: {
        'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
      },
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test theme preference with cookie
    print('\nGetting theme preference:');
    response = await client.get(
      Uri.parse('$baseUrl/theme'),
      headers: {
        'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
      },
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test deleting cookie
    print('\nDeleting cookie:');
    response = await client.get(Uri.parse('$baseUrl/delete-cookie'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
    print('Set-Cookie Header: ${response.headers['set-cookie']}');
  } finally {
    client.close();
  }
}
