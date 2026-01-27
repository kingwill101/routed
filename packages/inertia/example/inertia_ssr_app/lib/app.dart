import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

const String _clientEntry = 'src/main.jsx';

Future<void> serve({String address = '127.0.0.1', int port = 8080}) async {
  final server = await HttpServer.bind(address, port);
  stdout.writeln('Inertia SSR app listening on http://$address:$port');

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  if (await _tryServeStatic(request)) return;

  if (request.uri.path != '/') {
    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not Found');
    await request.response.close();
    return;
  }

  final inertiaRequest = inertiaRequestFromHttp(request);
  final context = inertiaRequest.createContext();
  final page = await InertiaResponseFactory().buildPageDataAsync(
    component: 'Home',
    props: {'title': 'Inertia SSR App', 'mode': 'ssr'},
    url: _requestUrl(request.uri),
    context: context,
  );

  if (inertiaRequest.isInertia) {
    await writeInertiaResponse(request.response, InertiaResponse.json(page));
    return;
  }

  final ssrResponse = await _renderSsr(page);
  final html = await _renderHtml(page, ssrResponse);
  await writeInertiaResponse(
    request.response,
    InertiaResponse.html(page, html),
  );
}

Future<SsrResponse?> _renderSsr(PageData page) async {
  print("_renderSSr called");
  final enabled = _boolEnv('INERTIA_SSR', defaultValue: true);
  if (!enabled) return null;
  print("render ssr actually happening");
  final endpoint =
      Platform.environment['INERTIA_SSR_URL'] ??
      'http://127.0.0.1:13714/render';
  final gateway = HttpSsrGateway(Uri.parse(endpoint));
  try {
    return await gateway.render(jsonEncode(page.toJson()));
  } catch (_) {
    return null;
  }
}

Future<bool> _tryServeStatic(HttpRequest request) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return false;
  }
  final path = request.uri.path;
  if (!path.startsWith('/assets/')) {
    return false;
  }

  final relative = path.startsWith('/') ? path.substring(1) : path;
  final file = File('client/dist/$relative');
  if (!file.existsSync()) {
    return false;
  }

  request.response.headers.contentType = _contentTypeForPath(path);
  await request.response.addStream(file.openRead());
  await request.response.close();
  return true;
}

Future<String> _renderHtml(PageData page, SsrResponse? ssr) async {
  final assets = InertiaViteAssets(
    entry: _clientEntry,
    manifestPath: 'client/dist/manifest.json',
    hotFile: 'client/public/hot',
    includeReactRefresh: true,
  );
  final tags = await assets.resolve();
  final pageJson = jsonEncode(page.toJson());
  final escaped = _escapeHtml(pageJson);
  final head = ssr?.head ?? '';
  final bodyContent = ssr?.body ?? '';
  final app = _resolveAppMarkup(bodyContent, escaped);

  return '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    $head
    ${tags.renderStyles()}
    <title>Inertia SSR App</title>
  </head>
  <body>
    $app
    ${tags.renderScripts()}
  </body>
</html>
''';
}

String _resolveAppMarkup(String bodyContent, String pageJson) {
  if (bodyContent.isEmpty) {
    return '<div id="app" data-page="$pageJson"></div>';
  }
  if (bodyContent.contains('id="app"')) {
    return bodyContent;
  }
  return '<div id="app" data-page="$pageJson">$bodyContent</div>';
}

String _requestUrl(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.hasQuery) {
    return '$path?${uri.query}';
  }
  return path;
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
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
  return ContentType.binary;
}

bool _boolEnv(String key, {required bool defaultValue}) {
  final raw = Platform.environment[key];
  if (raw == null) return defaultValue;
  final value = raw.toLowerCase().trim();
  if (value == 'true' || value == '1' || value == 'yes') return true;
  if (value == 'false' || value == '0' || value == 'no') return false;
  return defaultValue;
}
