library;

import 'dart:convert';
import 'dart:io';

import '../core/inertia_headers.dart';
import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import '../core/page_data.dart';

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

/// Escapes JSON text for safe embedding inside an HTML `<script>` tag.
///
/// This preserves valid JSON while preventing the browser from treating
/// characters like `<` as HTML markup.
String escapeInertiaJsonForScript(String value) {
  return value
      .replaceAll('&', r'\u0026')
      .replaceAll('<', r'\u003C')
      .replaceAll('>', r'\u003E')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
}

/// Renders the JSON bootstrap `<script>` element used by Inertia v3.
String inertiaPageScriptTag(PageData page, {String id = 'app'}) {
  final pageJson = jsonEncode(page.toJson());
  final safeId = escapeInertiaHtml(id);
  final safeJson = escapeInertiaJsonForScript(pageJson);
  return '<script data-page="$safeId" type="application/json">$safeJson</script>';
}

/// Renders the default Inertia v3 bootstrap markup.
String renderInertiaBootstrap(
  PageData page, {
  String id = 'app',
  String? body,
}) {
  final safeId = escapeInertiaHtml(id);
  final app = body == null || body.isEmpty
      ? '<div id="$safeId"></div>'
      : '<div id="$safeId">$body</div>';
  return '${inertiaPageScriptTag(page, id: id)}$app';
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
