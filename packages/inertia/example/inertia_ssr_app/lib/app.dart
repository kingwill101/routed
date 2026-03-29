import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

const String _clientEntry = 'index.html';
const InertiaViteAssets _assets = InertiaViteAssets(
  entry: _clientEntry,
  manifestPath: 'client/dist/.vite/manifest.json',
  hotFile: 'client/public/hot',
  includeReactRefresh: true,
);

Future<void> serve({String address = '127.0.0.1', int port = 8080}) async {
  final server = await HttpServer.bind(address, port);
  stdout.writeln('Inertia SSR app listening on http://$address:$port');

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  if (await tryWriteStaticAsset(request, rootDirectory: 'client/dist')) return;

  if (request.uri.path != '/') {
    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not Found');
    await request.response.close();
    return;
  }

  await respondWithInertiaPage(
    request,
    component: 'Home',
    props: {'title': 'Inertia SSR App', 'mode': 'ssr'},
    html: (page, ssr) => renderInertiaVitePageHtml(
      page,
      assets: _assets,
      title: 'Inertia SSR App',
      ssr: ssr,
    ),
    ssr: _renderSsr,
  );
}

Future<SsrResponse?> _renderSsr(PageData page) async {
  final enabled = _boolEnv('INERTIA_SSR', defaultValue: true);
  if (!enabled) return null;
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

bool _boolEnv(String key, {required bool defaultValue}) {
  final raw = Platform.environment[key];
  if (raw == null) return defaultValue;
  final value = raw.toLowerCase().trim();
  if (value == 'true' || value == '1' || value == 'yes') return true;
  if (value == 'false' || value == '0' || value == 'no') return false;
  return defaultValue;
}
