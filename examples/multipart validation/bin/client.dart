import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Create multipart request
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

  // Send request and get response
  var streamedResponse = await request.send();
  var response = await http.Response.fromStream(streamedResponse);

  print('Upload Response:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
