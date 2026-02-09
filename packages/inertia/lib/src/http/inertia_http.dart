library;

import 'dart:io';

import '../core/inertia_headers.dart';
import '../core/inertia_request.dart';
import '../core/inertia_response.dart';

/// Extracts a flat `Map<String, String>` from `dart:io` [HttpHeaders].
///
/// When [HttpHeaders.forEach] yields multiple values for a name, only the
/// first value is kept. Header names are stored as-is (lowercased by
/// `dart:io`).
///
/// ```dart
/// final headers = extractHttpHeaders(request.headers);
/// ```
Map<String, String> extractHttpHeaders(HttpHeaders headers) {
  final result = <String, String>{};
  headers.forEach((name, values) {
    if (values.isNotEmpty) {
      result[name] = values.first;
    }
  });
  return result;
}

/// Escapes HTML entities in [value] for safe embedding in HTML attributes.
///
/// Replaces `&`, `<`, `>`, `"`, and `'` with their HTML entity equivalents.
///
/// ```dart
/// final safe = escapeInertiaHtml('{"foo":"<bar>"}');
/// // => '{"foo":"&lt;bar&gt;"}'
/// ```
String escapeInertiaHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

/// Provides dart:io helpers for Inertia requests and responses.
///
/// ```dart
/// final request = inertiaRequestFromHttp(httpRequest);
/// final response = InertiaResponse.json(page);
/// await writeInertiaResponse(httpRequest.response, response);
/// ```
///
/// Builds an [InertiaRequest] from a `dart:io` [HttpRequest].
InertiaRequest inertiaRequestFromHttp(HttpRequest request) {
  final headers = extractHttpHeaders(request.headers);

  return InertiaRequest(
    headers: headers,
    url: request.uri.toString(),
    method: request.method,
  );
}

/// Writes an [InertiaResponse] to a `dart:io` [HttpResponse].
///
/// If the response is a location visit, the response is closed immediately.
Future<void> writeInertiaResponse(
  HttpResponse response,
  InertiaResponse inertiaResponse,
) async {
  response.statusCode = inertiaResponse.statusCode;
  inertiaResponse.headers.forEach(response.headers.set);

  if (inertiaResponse.headers.containsKey(InertiaHeaders.inertiaLocation)) {
    await response.close();
    return;
  }

  if (inertiaResponse.html != null) {
    response.write(inertiaResponse.html);
  } else {
    response.write(inertiaResponse.toJsonString());
  }
  await response.close();
}
