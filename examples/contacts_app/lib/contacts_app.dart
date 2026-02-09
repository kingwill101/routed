import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

// ---------------------------------------------------------------------------
// In-memory contact store
// ---------------------------------------------------------------------------

class ContactStore {
  int _nextId = 4;
  final List<Map<String, dynamic>> _contacts = [
    {'id': 1, 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    {'id': 2, 'name': 'Grace Hopper', 'email': 'grace@example.com'},
    {'id': 3, 'name': 'Alan Turing', 'email': 'alan@example.com'},
  ];

  List<Map<String, dynamic>> all() =>
      _contacts.map((c) => Map<String, dynamic>.from(c)).toList();

  void add(String name, String email) {
    _contacts.add({'id': _nextId++, 'name': name, 'email': email});
  }

  void remove(int id) {
    _contacts.removeWhere((c) => c['id'] == id);
  }
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const String _version = 'dev';
const String _clientEntry = 'index.html';
const String _manifestPath = 'client/dist/.vite/manifest.json';
const String _hotFile = 'client/public/hot';

Future<void> serve({String address = '127.0.0.1', int port = 8080}) async {
  final store = ContactStore();
  final server = await HttpServer.bind(address, port);
  stdout.writeln('Contacts app listening on http://$address:$port');

  await for (final httpRequest in server) {
    try {
      await _handleRequest(httpRequest, store);
    } catch (e, st) {
      stderr.writeln('Error handling ${httpRequest.uri}: $e\n$st');
      httpRequest.response.statusCode = HttpStatus.internalServerError;
      httpRequest.response.write('Internal Server Error');
      await httpRequest.response.close();
    }
  }
}

Future<void> _handleRequest(HttpRequest httpRequest, ContactStore store) async {
  // Serve static assets first
  if (await _tryServeStatic(httpRequest)) return;

  final method = httpRequest.method;
  final path = httpRequest.uri.path;

  // Parse the Inertia request
  final request = inertiaRequestFromHttp(httpRequest);
  final context = request.createContext();

  // Route: GET /
  if (method == 'GET' && path == '/') {
    final page = await InertiaResponseFactory().buildPageDataAsync(
      component: 'Home',
      props: {'title': 'Contacts App', 'subtitle': 'inertia_dart + dart:io'},
      url: _requestUrl(httpRequest.uri),
      context: context,
      version: _version,
    );
    await _respond(httpRequest, request, page);
    return;
  }

  // Route: GET /contacts
  if (method == 'GET' && path == '/contacts') {
    final page = await InertiaResponseFactory().buildPageDataAsync(
      component: 'Contacts',
      props: {'title': 'Contacts', 'contacts': store.all()},
      url: _requestUrl(httpRequest.uri),
      context: context,
      version: _version,
    );
    await _respond(httpRequest, request, page);
    return;
  }

  // Route: POST /contacts
  if (method == 'POST' && path == '/contacts') {
    final body = await _readJsonBody(httpRequest);
    final name = (body['name'] as String?)?.trim() ?? '';
    final email = (body['email'] as String?)?.trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) {
      store.add(name, email);
    }
    _redirect(httpRequest, '/contacts');
    return;
  }

  // Route: DELETE /contacts/{id}
  final deleteMatch = RegExp(r'^/contacts/(\d+)$').firstMatch(path);
  if (method == 'DELETE' && deleteMatch != null) {
    final id = int.parse(deleteMatch.group(1)!);
    store.remove(id);
    // Rewrite 302 -> 303 for DELETE (Inertia protocol requirement)
    _redirect(httpRequest, '/contacts', status: HttpStatus.seeOther);
    return;
  }

  // 404
  httpRequest.response.statusCode = HttpStatus.notFound;
  httpRequest.response.write('Not Found');
  await httpRequest.response.close();
}

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

Future<void> _respond(
  HttpRequest httpRequest,
  InertiaRequest request,
  PageData page,
) async {
  if (request.isInertia) {
    await writeInertiaResponse(
      httpRequest.response,
      InertiaResponse.json(page),
    );
    return;
  }

  final html = await _renderHtml(page);
  await writeInertiaResponse(
    httpRequest.response,
    InertiaResponse.html(page, html),
  );
}

void _redirect(
  HttpRequest httpRequest,
  String location, {
  int status = HttpStatus.found,
}) {
  httpRequest.response.statusCode = status;
  httpRequest.response.headers.set(HttpHeaders.locationHeader, location);
  httpRequest.response.close();
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.isEmpty) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

// ---------------------------------------------------------------------------
// HTML rendering
// ---------------------------------------------------------------------------

Future<String> _renderHtml(PageData page) async {
  final assets = InertiaViteAssets(
    entry: _clientEntry,
    manifestPath: _manifestPath,
    hotFile: _hotFile,
    includeReactRefresh: true,
  );
  final tags = await assets.resolve();
  final pageJson = jsonEncode(page.toJson());
  final escaped = escapeInertiaHtml(pageJson);

  return '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Contacts App</title>
    ${tags.renderStyles()}
  </head>
  <body>
    <div id="app" data-page="$escaped"></div>
    ${tags.renderScripts()}
  </body>
</html>
''';
}

// ---------------------------------------------------------------------------
// Static file serving
// ---------------------------------------------------------------------------

Future<bool> _tryServeStatic(HttpRequest request) async {
  if (request.method != 'GET' && request.method != 'HEAD') return false;
  final path = request.uri.path;
  if (!path.startsWith('/assets/')) return false;

  final relative = path.startsWith('/') ? path.substring(1) : path;
  final file = File('client/dist/$relative');
  if (!file.existsSync()) return false;

  request.response.headers.contentType = _contentTypeForPath(path);
  await request.response.addStream(file.openRead());
  await request.response.close();
  return true;
}

ContentType _contentTypeForPath(String path) {
  if (path.endsWith('.js')) return ContentType('application', 'javascript');
  if (path.endsWith('.css')) return ContentType('text', 'css');
  if (path.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (path.endsWith('.png')) return ContentType('image', 'png');
  if (path.endsWith('.woff2')) return ContentType('font', 'woff2');
  return ContentType.binary;
}

String _requestUrl(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}
