import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed/providers.dart';
import 'package:routed_inertia/routed_inertia.dart';

void main() async {
  registerRoutedInertiaProvider(ProviderRegistry.instance);

  final devServer = Platform.environment['INERTIA_DEV'] != 'false';
  final engine = Engine(
    providers: [
      CoreServiceProvider.withLoader(
        ConfigLoaderOptions(
          configDirectory: 'packages/routed_inertia/example/config',
        ),
      ),
      RoutingServiceProvider(),
    ],
    options: [
      if (!devServer)
        withStaticAssets(
          enabled: true,
          route: '/assets',
          directory: 'packages/routed_inertia/example/client/dist/assets',
        ),
    ],
  );

  final config = _resolveInertiaConfig(engine);
  final assets = devServer
      ? _devAssetTags(_resolveDevServerOrigin(config?.assets))
      : await _loadManifestAssets(config?.assets);
  String htmlBuilder(PageData page, SsrResponse? ssr) =>
      _renderHtml(page, assets: assets);

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
      htmlBuilder: htmlBuilder,
    );
  });

  await engine.serve(port: 8080);
}

String _renderHtml(PageData page, {required AssetTags assets}) {
  final title = page.props['title']?.toString() ?? 'Routed Inertia';
  final pageJson = jsonEncode(page.toJson());
  final escaped = _escapeHtml(pageJson);
  final styleTags = assets.styles.join('\n    ');
  final scriptTags = assets.scripts.join('\n    ');

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
    ${scriptTags.trim()}
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

class AssetTags {
  const AssetTags({this.styles = const [], this.scripts = const []});

  final List<String> styles;
  final List<String> scripts;
}

AssetTags _devAssetTags(String devOrigin) {
  final scripts = <String>[
    '<script type="module" src="$devOrigin/@vite/client"></script>',
    '''<script type="module">
  import RefreshRuntime from '$devOrigin/@react-refresh'
  RefreshRuntime.injectIntoGlobalHook(window)
  window.
    \$RefreshReg\$ = () => {}
  window.
    \$RefreshSig\$ = () => (type) => type
  window.
    __vite_plugin_react_preamble_installed__ = true
</script>''',
    '<script type="module" src="$devOrigin/src/main.jsx"></script>',
  ];

  return AssetTags(scripts: scripts);
}

String _resolveDevServerOrigin(InertiaAssetsConfig? assets) {
  final env = Platform.environment;
  final direct = env['INERTIA_DEV_SERVER_URL'] ?? env['VITE_DEV_SERVER_URL'];
  if (direct != null && direct.trim().isNotEmpty) {
    return _trimTrailingSlash(direct.trim());
  }

  final configUrl = assets?.resolveDevServerUrl();
  if (configUrl != null && configUrl.isNotEmpty) {
    return _trimTrailingSlash(configUrl);
  }

  final hotFile = File('packages/routed_inertia/example/client/public/hot');
  if (hotFile.existsSync()) {
    final contents = hotFile.readAsStringSync().trim();
    if (contents.isNotEmpty) {
      return _trimTrailingSlash(contents);
    }
  }

  final host = env['INERTIA_DEV_SERVER_HOST'] ?? env['VITE_DEV_SERVER_HOST'];
  final port = env['INERTIA_DEV_SERVER_PORT'] ?? env['VITE_DEV_SERVER_PORT'];
  if (host == null || host.trim().isEmpty || port == null || port.isEmpty) {
    throw StateError(
      'Set INERTIA_DEV_SERVER_URL (or VITE_DEV_SERVER_URL), provide '
      'INERTIA_DEV_SERVER_HOST and INERTIA_DEV_SERVER_PORT, or start Vite '
      'with the hot file enabled for dev mode.',
    );
  }

  final scheme =
      env['INERTIA_DEV_SERVER_SCHEME'] ??
      env['VITE_DEV_SERVER_SCHEME'] ??
      'http';
  return _trimTrailingSlash('$scheme://${host.trim()}:${port.trim()}');
}

Future<AssetTags> _loadManifestAssets(InertiaAssetsConfig? assets) async {
  final manifestPath =
      assets?.manifestPath ??
      'packages/routed_inertia/example/client/dist/.vite/manifest.json';
  final entry = assets?.entry ?? 'src/main.jsx';
  final baseUrl = assets?.baseUrl ?? '/';
  final manifestFile = File(manifestPath);

  if (!manifestFile.existsSync()) {
    return const AssetTags(
      scripts: ['<script type="module" src="/assets/main.js"></script>'],
    );
  }

  final manifest = await InertiaAssetManifest.load(manifestPath);
  final styles = manifest.styleTags(entry, baseUrl: baseUrl);
  final scripts = manifest.scriptTags(entry, baseUrl: baseUrl);
  return AssetTags(styles: styles, scripts: scripts);
}

InertiaConfig? _resolveInertiaConfig(Engine engine) {
  if (!engine.container.has<InertiaConfig>()) {
    return null;
  }
  try {
    return engine.container.get<InertiaConfig>();
  } catch (_) {
    return null;
  }
}

String _trimTrailingSlash(String value) {
  if (value.endsWith('/')) {
    return value.substring(0, value.length - 1);
  }
  return value;
}
