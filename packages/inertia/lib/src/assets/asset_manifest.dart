library;

import 'dart:convert';
import 'dart:io';

import 'asset_manifest_entry.dart';
import 'asset_resolution.dart';

/// Loads and resolves Vite-style asset manifests for Inertia apps.
///
/// ```dart
/// final manifest = await InertiaAssetManifest.load('build/manifest.json');
/// final tags = manifest.renderTags('resources/js/app.js', baseUrl: '/');
/// ```
class InertiaAssetManifest {
  /// Creates a manifest from pre-parsed [entries].
  InertiaAssetManifest(this.entries);

  /// Creates a manifest from a decoded JSON map.
  factory InertiaAssetManifest.fromJson(Map<String, dynamic> json) {
    final entries = <String, InertiaAssetManifestEntry>{};
    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        entries[key] = InertiaAssetManifestEntry.fromJson(value);
      } else if (value is Map) {
        entries[key] = InertiaAssetManifestEntry.fromJson(
          Map<String, dynamic>.from(value),
        );
      }
    });
    return InertiaAssetManifest(entries);
  }

  /// Creates a manifest from a JSON string.
  ///
  /// #### Throws
  /// - [ArgumentError] if the JSON does not represent an object.
  factory InertiaAssetManifest.fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is Map<String, dynamic>) {
      return InertiaAssetManifest.fromJson(decoded);
    }
    if (decoded is Map) {
      return InertiaAssetManifest.fromJson(Map<String, dynamic>.from(decoded));
    }
    throw ArgumentError('Manifest JSON must be an object.');
  }

  /// Loads and parses the manifest file at [path].
  static Future<InertiaAssetManifest> load(String path) async {
    final file = File(path);
    final contents = await file.readAsString();
    return InertiaAssetManifest.fromJsonString(contents);
  }

  /// Manifest entries keyed by source path.
  final Map<String, InertiaAssetManifestEntry> entries;

  /// Returns the manifest entry for [source], if present.
  InertiaAssetManifestEntry? entry(String source) => entries[source];

  /// Resolves all assets needed for [source], including imports and CSS.
  InertiaAssetResolution resolve(String source) {
    final resolvedCss = <String>[];
    final resolvedImports = <String>[];
    final resolvedAssets = <String>[];
    final visited = <String>{};

    void visit(String key) {
      if (visited.contains(key)) return;
      visited.add(key);
      final entry = entries[key];
      if (entry == null) return;

      for (final importKey in entry.imports) {
        visit(importKey);
        final importEntry = entries[importKey];
        if (importEntry != null && importEntry.file.isNotEmpty) {
          _appendUnique(resolvedImports, importEntry.file);
        }
      }

      for (final cssFile in entry.css) {
        _appendUnique(resolvedCss, cssFile);
      }

      for (final asset in entry.assets) {
        _appendUnique(resolvedAssets, asset);
      }
    }

    visit(source);

    final entry = entries[source];
    final file = entry?.file.isNotEmpty == true ? entry!.file : null;
    return InertiaAssetResolution(
      file: file,
      css: resolvedCss,
      imports: resolvedImports,
      assets: resolvedAssets,
    );
  }

  /// Returns script tags for [source].
  List<String> scriptTags(String source, {String baseUrl = ''}) {
    final resolution = resolve(source);
    if (resolution.file == null) return const [];
    final src = _withBaseUrl(baseUrl, resolution.file!);
    return ['<script type="module" src="$src"></script>'];
  }

  /// Returns style tags for [source].
  List<String> styleTags(String source, {String baseUrl = ''}) {
    final resolution = resolve(source);
    return resolution.css
        .map((css) => _withBaseUrl(baseUrl, css))
        .map((href) => '<link rel="stylesheet" href="$href">')
        .toList();
  }

  /// Renders all tags for [source] into a single HTML string.
  String renderTags(String source, {String baseUrl = ''}) {
    final tags = [
      ...styleTags(source, baseUrl: baseUrl),
      ...scriptTags(source, baseUrl: baseUrl),
    ];
    return tags.join('\n');
  }
}

/// Appends [value] to [target] if it is not already present.
void _appendUnique(List<String> target, String value) {
  if (!target.contains(value)) {
    target.add(value);
  }
}

/// Prepends [baseUrl] to [path] when [baseUrl] is non-empty.
String _withBaseUrl(String baseUrl, String path) {
  if (baseUrl.isEmpty) return path;
  final trimmedBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final trimmedPath = path.startsWith('/') ? path.substring(1) : path;
  return '$trimmedBase/$trimmedPath';
}
