import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;

/// Utilities for translating between HttpRequest/HttpResponse and shelf Request/Response.
class ShelfTranslator {
  /// Converts an HttpRequest to a shelf Request.
  ///
  /// This method extracts all the necessary information from the HttpRequest
  /// (method, url, headers, body) and creates an equivalent shelf Request.
  static Future<shelf.Request> httpRequestToShelfRequest(
    HttpRequest httpRequest,
  ) async {
    // Extract method and URL
    final method = httpRequest.method;
    final url = httpRequest.uri;

    // Convert headers
    final headers = <String, String>{};
    httpRequest.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(',');
    });

    // Read the request body
    final body = await _readHttpRequestBody(httpRequest);
    // Create the shelf Request
    return shelf.Request(
      method,
      url,
      headers: headers,
      body: body,
      context: {},
      encoding: _getEncodingFromHeaders(httpRequest.headers),
      protocolVersion: httpRequest.protocolVersion,
    );
  }

  /// Writes a shelf Response to an HttpResponse.
  ///
  /// This method takes a shelf Response and writes its status code, headers,
  /// and body to the HttpResponse.
  static Future<void> writeShelfResponseToHttpResponse(
    shelf.Response shelfResponse,
    HttpResponse httpResponse,
  ) async {
    // Set status code
    httpResponse.statusCode = shelfResponse.statusCode;

    // Set headers
    shelfResponse.headers.forEach((name, value) {
      httpResponse.headers.add(name, value);
    });

    // Write body. Avoid double-closing the response by manually piping chunks.
    await for (final chunk in shelfResponse.read()) {
      httpResponse.add(chunk);
    }
    await httpResponse.close();
  }

  /// Reads the body of an HttpRequest as a list of bytes.
  static Future<List<int>> _readHttpRequestBody(HttpRequest request) async {
    final completer = Completer<List<int>>();
    final bodyBytes = <int>[];

    request.listen(
      bodyBytes.addAll,
      onDone: () => completer.complete(bodyBytes),
      onError: completer.completeError,
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Determines the encoding from the Content-Type header.
  static Encoding _getEncodingFromHeaders(HttpHeaders headers) {
    final contentType = headers.contentType;
    if (contentType == null) return utf8;

    final charset = contentType.charset;
    if (charset == null) return utf8;

    return Encoding.getByName(charset) ?? utf8;
  }
}
