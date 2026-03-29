library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../assets/vite_assets.dart';
import '../core/inertia_headers.dart';
import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import '../core/page_data.dart';
import '../core/response_factory.dart';
import '../property_context.dart';
import '../ssr/ssr_response.dart';

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

/// Builds props for a raw `dart:io` Inertia request.
typedef InertiaHttpPropsBuilder =
    FutureOr<Map<String, dynamic>> Function(
      HttpRequest request,
      InertiaRequest inertiaRequest,
    );

/// Renders HTML for a raw `dart:io` Inertia request.
typedef InertiaHttpHtmlBuilder =
    FutureOr<String> Function(PageData page, SsrResponse? ssrResponse);

/// Resolves an optional SSR response for a raw `dart:io` Inertia request.
typedef InertiaHttpSsrBuilder = FutureOr<SsrResponse?> Function(PageData page);

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

/// Builds page data for a raw `dart:io` Inertia request.
Future<PageData> buildInertiaHttpPageData(
  HttpRequest request, {
  required String component,
  required Map<String, dynamic> props,
  String? url,
  PropertyContext? context,
  String version = '',
  bool encryptHistory = false,
  bool clearHistory = false,
  Map<String, dynamic>? flash,
  List<int>? cache,
  InertiaResponseFactory? responseFactory,
}) async {
  final inertiaRequest = inertiaRequestFromHttp(request);
  final resolvedContext = context ?? inertiaRequest.createContext();

  return await (responseFactory ?? InertiaResponseFactory()).buildPageDataAsync(
    component: component,
    props: props,
    url: url ?? _requestUrl(request.uri),
    context: resolvedContext,
    version: version,
    encryptHistory: encryptHistory,
    clearHistory: clearHistory,
    flash: flash,
    cache: cache,
  );
}

/// Builds an Inertia response for a raw `dart:io` request.
Future<InertiaResponse> buildInertiaHttpResponse(
  HttpRequest request, {
  required String component,
  required Map<String, dynamic> props,
  required InertiaHttpHtmlBuilder html,
  InertiaHttpSsrBuilder? ssr,
  String? url,
  PropertyContext? context,
  String version = '',
  bool encryptHistory = false,
  bool clearHistory = false,
  Map<String, dynamic>? flash,
  List<int>? cache,
  int statusCode = 200,
  InertiaResponseFactory? responseFactory,
}) async {
  final page = await buildInertiaHttpPageData(
    request,
    component: component,
    props: props,
    url: url,
    context: context,
    version: version,
    encryptHistory: encryptHistory,
    clearHistory: clearHistory,
    flash: flash,
    cache: cache,
    responseFactory: responseFactory,
  );

  final inertiaRequest = inertiaRequestFromHttp(request);
  if (inertiaRequest.isInertia) {
    return InertiaResponse.json(page, statusCode: statusCode);
  }

  final ssrResponse = ssr == null ? null : await ssr(page);
  final htmlBody = await html(page, ssrResponse);
  return InertiaResponse.html(page, htmlBody, statusCode: statusCode);
}

/// Builds and writes a page response for a raw `dart:io` request.
Future<InertiaResponse> respondWithInertiaPage(
  HttpRequest request, {
  required String component,
  required Map<String, dynamic> props,
  required InertiaHttpHtmlBuilder html,
  InertiaHttpSsrBuilder? ssr,
  String? url,
  PropertyContext? context,
  String version = '',
  bool encryptHistory = false,
  bool clearHistory = false,
  Map<String, dynamic>? flash,
  List<int>? cache,
  int statusCode = 200,
  InertiaResponseFactory? responseFactory,
}) async {
  final response = await buildInertiaHttpResponse(
    request,
    component: component,
    props: props,
    html: html,
    ssr: ssr,
    url: url,
    context: context,
    version: version,
    encryptHistory: encryptHistory,
    clearHistory: clearHistory,
    flash: flash,
    cache: cache,
    statusCode: statusCode,
    responseFactory: responseFactory,
  );
  await writeInertiaResponse(request.response, response);
  return response;
}

/// Renders a simple HTML document using Vite asset tags.
Future<String> renderInertiaVitePageHtml(
  PageData page, {
  required InertiaViteAssets assets,
  String title = 'Inertia',
  String lang = 'en',
  SsrResponse? ssr,
}) async {
  final tags = await assets.resolve();
  final head = ssr?.head ?? '';

  return '''<!doctype html>
<html lang="$lang">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    $head
    ${tags.renderStyles()}
    <title>$title</title>
  </head>
  <body>
    ${renderInertiaBootstrap(page, body: ssr?.body)}
    ${tags.renderScripts()}
  </body>
</html>
''';
}

/// Serves a static asset from [rootDirectory] when [request] targets [pathPrefix].
Future<bool> tryWriteStaticAsset(
  HttpRequest request, {
  required String rootDirectory,
  String pathPrefix = '/assets/',
}) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return false;
  }

  final path = request.uri.path;
  if (!path.startsWith(pathPrefix)) {
    return false;
  }

  final relative = path.startsWith('/') ? path.substring(1) : path;
  final file = File('$rootDirectory/$relative');
  if (!file.existsSync()) {
    return false;
  }

  request.response.headers.contentType = _contentTypeForPath(path);
  await request.response.addStream(file.openRead());
  await request.response.close();
  return true;
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

String _requestUrl(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.hasQuery) {
    return '$path?${uri.query}';
  }
  return path;
}

ContentType _contentTypeForPath(String path) {
  if (path.endsWith('.js')) {
    return ContentType('application', 'javascript');
  }
  if (path.endsWith('.css')) {
    return ContentType('text', 'css');
  }
  if (path.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }
  if (path.endsWith('.json')) {
    return ContentType('application', 'json');
  }
  return ContentType.binary;
}
