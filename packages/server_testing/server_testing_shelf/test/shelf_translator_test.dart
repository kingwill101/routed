import 'dart:convert';
import 'dart:typed_data';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/src/shelf_translator.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  group('ShelfTranslator Tests', () {
    test(
      'httpRequestToShelfRequest converts HttpRequest to shelf Request',
      () async {
        // Create a mock HttpRequest
        final mockRequest = setupRequest(
          'GET',
          '/test?q=value',
          requestHeaders: {
            'Content-Type': ['application/json'],
            'User-Agent': ['test-agent'],
            'Accept': ['application/json'],
          },
          body: '{"key": "value"}',
        );

        // Convert to shelf Request
        final shelfRequest = await ShelfTranslator.httpRequestToShelfRequest(
          mockRequest,
        );

        // Verify conversion
        expect(shelfRequest.method, equals('GET'));
        expect(shelfRequest.url.path, equals('test'));
        expect(shelfRequest.url.queryParameters['q'], equals('value'));
        expect(
          shelfRequest.headers['content-type'],
          equals('application/json; charset=utf-8'),
        );
        expect(shelfRequest.headers['user-agent'], equals('test-agent'));
        expect(shelfRequest.headers['accept'], equals('application/json'));

        // Verify body
        final body = await shelfRequest.readAsString();
        expect(body, equals('{"key": "value"}'));
      },
    );

    test(
      'writeShelfResponseToHttpResponse writes shelf Response to HttpResponse',
      () async {
        // Create a mock HttpResponse
        final responseHeaders = <String, List<String>>{};
        final responseBody = BytesBuilder();
        final mockResponse = setupResponse(
          headers: responseHeaders,
          body: responseBody,
        );

        // Create a shelf Response
        final shelfResponse = shelf.Response(
          200,
          body: 'Test response body',
          headers: {
            'Content-Type': 'text/plain',
            'X-Test-Header': 'test-value',
          },
        );

        // Write shelf Response to HttpResponse
        await ShelfTranslator.writeShelfResponseToHttpResponse(
          shelfResponse,
          mockResponse,
        );

        // Verify response
        verify(mockResponse.statusCode = 200).called(1);
        expect(responseHeaders['Content-Type'], contains('text/plain'));
        expect(responseHeaders['X-Test-Header'], contains('test-value'));
        expect(
          utf8.decode(responseBody.takeBytes()),
          equals('Test response body'),
        );
      },
    );

    test('Handles empty response body', () async {
      // Create a mock HttpResponse
      final responseHeaders = <String, List<String>>{};
      final responseBody = BytesBuilder();
      final mockResponse = setupResponse(
        headers: responseHeaders,
        body: responseBody,
      );

      // Create a shelf Response with no body
      final shelfResponse = shelf.Response(204);

      // Write shelf Response to HttpResponse
      await ShelfTranslator.writeShelfResponseToHttpResponse(
        shelfResponse,
        mockResponse,
      );

      // Verify response
      verify(mockResponse.statusCode = 204).called(1);
      expect(responseBody.length, equals(0));
    });

    test('Handles binary response body', () async {
      // Create a mock HttpResponse
      final responseHeaders = <String, List<String>>{};
      final responseBody = BytesBuilder();
      final mockResponse = setupResponse(
        headers: responseHeaders,
        body: responseBody,
      );

      // Create binary data (a simple image representation)
      final binaryData = [
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
      ];

      // Create a shelf Response with binary body
      final shelfResponse = shelf.Response(
        200,
        body: binaryData,
        headers: {'Content-Type': 'image/jpeg'},
      );

      // Write shelf Response to HttpResponse
      await ShelfTranslator.writeShelfResponseToHttpResponse(
        shelfResponse,
        mockResponse,
      );

      // Verify response
      verify(mockResponse.statusCode = 200).called(1);
      expect(responseHeaders['Content-Type'], contains('image/jpeg'));

      // Compare bytes
      final bytes = responseBody.takeBytes();
      expect(bytes, equals(binaryData));
    });
  });
}
