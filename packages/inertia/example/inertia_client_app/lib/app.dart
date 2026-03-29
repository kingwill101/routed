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
  stdout.writeln('Inertia client app listening on http://$address:$port');

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
    props: {'title': 'Inertia Client App', 'mode': 'client'},
    html: (page, _) => renderInertiaVitePageHtml(
      page,
      assets: _assets,
      title: 'Inertia Client App',
    ),
  );
}
