import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test JSON binding
  var response = await http.post(
    Uri.parse('$baseUrl/json'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': 'test',
      'age': 25,
      'tags': ['one', 'two']
    }),
  );
  print('JSON Binding Response: ${response.body}');

  // Test form URL encoded binding
  response = await http.post(
    Uri.parse('$baseUrl/form'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'name=test&age=25',
  );
  print('Form URL Encoded Binding Response: ${response.body}');

  // Test query binding
  response = await http.get(
    Uri.parse('$baseUrl/search?q=test&page=1&sort=desc'),
  );
  print('Query Binding Response: ${response.body}');

  // Test multipart form binding
  var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'))
    ..fields['name'] = 'test'
    ..fields['age'] = '25'
    ..fields['hobby'] = 'reading'
    ..fields['tags'] = 'one'
    ..fields['tags'] = 'two'
    ..fields['pref_theme'] = 'dark'
    ..fields['pref_lang'] = 'en'
    ..files.add(http.MultipartFile.fromBytes(
      'document',
      utf8.encode('Hello World'),
      filename: 'test.txt',
      contentType: MediaType.parse('text/plain'),
    ));

  response = await http.Response.fromStream(await request.send());
  print('Multipart Form Binding Response: ${response.body}');
}
