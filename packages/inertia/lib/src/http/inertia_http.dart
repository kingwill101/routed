library;

import 'dart:io';

import '../core/inertia_headers.dart';
import '../core/inertia_request.dart';
import '../core/inertia_response.dart';

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
  final headers = <String, String>{};
  request.headers.forEach((name, values) {
    if (values.isNotEmpty) {
      headers[name] = values.first;
    }
  });

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
