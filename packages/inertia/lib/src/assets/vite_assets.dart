library;

import 'dart:io';

import 'asset_manifest.dart';
import 'vite_asset_tags.dart';

/// Resolves Vite assets for development and production builds.
///
/// ```dart
/// final assets = InertiaViteAssets(entry: 'index.html');
/// final tags = await assets.resolve();
/// ```
class InertiaViteAssets {
  /// Creates a Vite asset resolver.
  const InertiaViteAssets({
    required this.entry,
    this.manifestPath = 'client/dist/.vite/manifest.json',
    this.hotFile = 'client/public/hot',
    this.baseUrl = '/',
    this.devServerUrl,
    this.includeReactRefresh = false,
    this.fallbackScript = '/assets/main.js',
  });

  /// The Vite entry file path.
  final String entry;

  /// Path to the Vite manifest file.
  final String manifestPath;

  /// Path to the Vite hot file used in dev mode.
  final String hotFile;

  /// Base URL used when rendering production tags.
  final String baseUrl;

  /// Dev server URL override, if known.
  final String? devServerUrl;

  /// Whether to inject the React refresh preamble.
  final bool includeReactRefresh;

  /// Fallback script path when the manifest is missing.
  final String? fallbackScript;

  /// Resolves tag bundles for the current environment.
  Future<InertiaViteAssetTags> resolve() async {
    final devOrigin = devServerUrl ?? _readHotFile();
    if (devOrigin != null) {
      return _devTags(devOrigin);
    }

    return _manifestTags();
  }

  /// Reads the dev server URL from the hot file, if present.
  String? _readHotFile() {
    final file = File(hotFile);
    if (!file.existsSync()) return null;
    final contents = file.readAsStringSync().trim();
    if (contents.isEmpty) return null;
    return _trimTrailingSlash(contents);
  }

  /// Builds asset tags for dev mode.
  InertiaViteAssetTags _devTags(String origin) {
    final scripts = <String>[
      '<script type="module" src="$origin/@vite/client"></script>',
    ];
    if (includeReactRefresh) {
      scripts.add(_reactRefreshPreamble(origin));
    }
    scripts.add(
      '<script type="module" src="${_resolveDevEntry(origin)}"></script>',
    );

    return InertiaViteAssetTags(
      scripts: scripts,
      styles: const [],
      devServerUrl: origin,
    );
  }

  /// Builds asset tags from the manifest, with fallbacks when needed.
  Future<InertiaViteAssetTags> _manifestTags() async {
    final manifestFile = File(manifestPath);
    if (!manifestFile.existsSync()) {
      final fallback = fallbackScript;
      if (fallback == null || fallback.trim().isEmpty) {
        return const InertiaViteAssetTags();
      }
      return InertiaViteAssetTags(
        scripts: [
          '<script type="module" src="${_withBaseUrl(fallback)}"></script>',
        ],
      );
    }

    final manifest = await InertiaAssetManifest.load(manifestPath);
    final scripts = manifest.scriptTags(entry, baseUrl: baseUrl);
    final styles = manifest.styleTags(entry, baseUrl: baseUrl);

    if (scripts.isEmpty) {
      final fallback = fallbackScript;
      if (fallback != null && fallback.trim().isNotEmpty) {
        return InertiaViteAssetTags(
          scripts: [
            '<script type="module" src="${_withBaseUrl(fallback)}"></script>',
          ],
          styles: styles,
        );
      }
    }

    return InertiaViteAssetTags(scripts: scripts, styles: styles);
  }

  /// Resolves the dev server entry URL.
  String _resolveDevEntry(String origin) {
    final trimmed = entry.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final path = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return '$origin/$path';
  }

  /// Returns the React refresh preamble script tag.
  String _reactRefreshPreamble(String origin) {
    return '''<script type="module">
  import RefreshRuntime from '$origin/@react-refresh'
  RefreshRuntime.injectIntoGlobalHook(window)
  window.
    \$RefreshReg\$ = () => {}
  window.
    \$RefreshSig\$ = () => (type) => type
  window.
    __vite_plugin_react_preamble_installed__ = true
</script>''';
  }

  /// Applies [baseUrl] to a relative [path].
  String _withBaseUrl(String path) {
    if (baseUrl.isEmpty) return path;
    final trimmedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final trimmedPath = path.startsWith('/') ? path.substring(1) : path;
    return '$trimmedBase/$trimmedPath';
  }

  /// Trims a trailing slash from [value], if present.
  String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
