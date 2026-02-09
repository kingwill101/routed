import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

const String _clientEntry = 'index.html';

Future<void> serve({String address = '127.0.0.1', int port = 8080}) async {
  final server = await HttpServer.bind(address, port);
  stdout.writeln('Inertia client app listening on http://$address:$port');

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
    props: {'title': 'Inertia Client App', 'mode': 'client'},
    url: _requestUrl(request.uri),
    context: context,
  );

  if (inertiaRequest.isInertia) {
    await writeInertiaResponse(request.response, InertiaResponse.json(page));
    return;
  }

  final html = await _renderHtml(page);
  await writeInertiaResponse(
    request.response,
    InertiaResponse.html(page, html),
  );
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

Future<String> _renderHtml(PageData page) async {
  final assets = InertiaViteAssets(
    entry: _clientEntry,
    manifestPath: 'client/dist/.vite/manifest.json',
    hotFile: 'client/public/hot',
    includeReactRefresh: true,
  );
  final tags = await assets.resolve();
  final pageJson = jsonEncode(page.toJson());
  final escaped = _escapeHtml(pageJson);

  return '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    ${tags.renderStyles()}
    <title>Inertia Client App</title>
  </head>
  <body>
    <div id="app" data-page="$escaped"></div>
    ${tags.renderScripts()}
  </body>
</html>
''';
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
