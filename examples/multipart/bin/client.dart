import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  // Step 1. Build the multipart request using the http package.
  final multipartRequest =
      http.MultipartRequest('POST', Uri.parse('http://localhost:8080/upload'))
        ..fields['name'] = 'test'
        ..fields['age'] = '25'
        // Note: Because 'fields' is a Map, adding two entries with the same key
        // will overwrite the first. To send multiple values for a field, use
        // different keys (like 'tags[]') or add additional parts.
        ..fields['tags'] = 'tag1, tag2'
        ..files.add(
          http.MultipartFile.fromBytes(
            'document',
            "Sometext".codeUnits,
            filename: "filename.txt",
          ),
        );

  // (Optional) If you want to inspect the headers:
  // print(multipartRequest.headers);

  // Step 2. Finalize the request to get the byte stream of the body.
  final http.ByteStream byteStream = multipartRequest.finalize();
  // Collect the body as a list of bytes.
  final List<int> bodyBytes = await byteStream.toBytes();

  // (Optional) You can print the generated body as a string.
  // print(utf8.decode(bodyBytes));

  // Step 3. Create a dart:io HttpClient and use it to send a POST request with the generated body.
  final uri = Uri.parse('http://localhost:8080/upload');
  final httpClient = HttpClient();

  try {
    final HttpClientRequest clientRequest = await httpClient.postUrl(uri);

    // Copy the headers from the multipart request.
    multipartRequest.headers.forEach((name, value) {
      clientRequest.headers.set(name, value);
    });
    // Set the content-length header (optional but recommended).
    clientRequest.contentLength = bodyBytes.length;

    // Write the generated body bytes.
    clientRequest.add(bodyBytes);

    // Send the request.
    final HttpClientResponse clientResponse = await clientRequest.close();
    final responseBody = await clientResponse.transform(utf8.decoder).join();
    print('Upload response (${clientResponse.statusCode}): $responseBody');
  } catch (e) {
    print('Error: $e');
  } finally {
    httpClient.close();
  }
}
