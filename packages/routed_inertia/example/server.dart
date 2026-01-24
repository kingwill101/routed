import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia.dart';
import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';

void main() async {
  final version = 'dev';
  final devServer = Platform.environment['INERTIA_DEV'] != 'false';
  final assets = devServer ? ViteAssetLinks.dev() : _loadViteAssets();
  final htmlBuilder = (PageData page, SsrResponse? ssr) =>
      _renderHtml(page, assets: assets);

  final engine = Engine(
    options: [
      withMiddleware([
        RoutedInertiaMiddleware(versionResolver: () => version).call,
      ]),
      if (!devServer)
        withStaticAssets(
          enabled: true,
          route: '/assets',
          directory: 'packages/routed_inertia/example/client/dist/assets',
        ),
    ],
  );

  engine.get('/', (ctx) {
    return ctx.inertia(
      'Home',
      props: {
        'title': 'Routed + Inertia',
        'subtitle': 'Server-driven pages with a React frontend',
        'links': [
          {'label': 'Home', 'href': '/'},
          {'label': 'Users', 'href': '/users'},
        ],
      },
      version: version,
      htmlBuilder: htmlBuilder,
    );
  });

  engine.get('/users', (ctx) {
    return ctx.inertia(
      'Users/Index',
      props: {
        'title': 'Users',
        'users': [
          {'id': 1, 'name': 'Ada Lovelace'},
          {'id': 2, 'name': 'Grace Hopper'},
          {'id': 3, 'name': 'Alan Turing'},
        ],
        'links': [
          {'label': 'Home', 'href': '/'},
          {'label': 'Users', 'href': '/users'},
        ],
      },
      version: version,
      htmlBuilder: htmlBuilder,
    );
  });

  await engine.serve(port: 8080);
}

String _renderHtml(PageData page, {required ViteAssetLinks assets}) {
  final title = page.props['title']?.toString() ?? 'Routed Inertia';
  final pageJson = jsonEncode(page.toJson());
  final escaped = _escapeHtml(pageJson);
  final scriptTags = StringBuffer();
  if (assets.viteClient != null) {
    scriptTags.writeln(
      '<script type="module" src="${assets.viteClient}"></script>',
    );
    scriptTags.writeln('''<script type="module">
  import RefreshRuntime from 'http://localhost:5173/@react-refresh'
  RefreshRuntime.injectIntoGlobalHook(window)
  window.
    \$RefreshReg\$ = () => {}
  window.
    \$RefreshSig\$ = () => (type) => type
  window.
    __vite_plugin_react_preamble_installed__ = true
</script>''');
  }
  scriptTags.writeln(
    '<script type="module" src="${assets.scriptSrc}"></script>',
  );
  final styleTags = assets.styleHrefs
      .map((href) => '<link rel="stylesheet" href="$href" />')
      .join('\n    ');

  return '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$title</title>
    ${styleTags.isEmpty ? '' : styleTags}
  </head>
  <body>
    <div id="app" data-page="$escaped"></div>
    ${scriptTags.toString().trim()}
  </body>
</html>
''';
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

class ViteAssetLinks {
  final String scriptSrc;
  final List<String> styleHrefs;
  final String? viteClient;

  const ViteAssetLinks({
    required this.scriptSrc,
    this.styleHrefs = const [],
    this.viteClient,
  });

  factory ViteAssetLinks.dev() {
    return const ViteAssetLinks(
      scriptSrc: 'http://localhost:5173/src/main.jsx',
      viteClient: 'http://localhost:5173/@vite/client',
    );
  }
}

ViteAssetLinks _loadViteAssets() {
  final manifestFile = File(
    'packages/routed_inertia/example/client/dist/.vite/manifest.json',
  );

  if (!manifestFile.existsSync()) {
    return const ViteAssetLinks(scriptSrc: '/assets/main.js');
  }

  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final entry = manifest['src/main.jsx'] as Map<String, dynamic>?;
  final scriptFile = entry?['file'] as String?;
  final cssFiles = (entry?['css'] as List?)?.cast<String>() ?? const [];

  return ViteAssetLinks(
    scriptSrc: scriptFile == null ? '/assets/main.js' : '/$scriptFile',
    styleHrefs: cssFiles.map((file) => '/$file').toList(),
  );
}
