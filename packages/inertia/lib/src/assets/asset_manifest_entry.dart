/// Defines a single entry from a Vite asset manifest.
///
/// ```dart
/// final entry = InertiaAssetManifestEntry.fromJson(json);
/// ```
class InertiaAssetManifestEntry {
  /// Creates a manifest entry with explicit fields.
  const InertiaAssetManifestEntry({
    required this.file,
    required this.src,
    this.css = const [],
    this.assets = const [],
    this.imports = const [],
    this.isEntry = false,
  });

  /// Creates a manifest entry from decoded JSON.
  factory InertiaAssetManifestEntry.fromJson(Map<String, dynamic> json) {
    return InertiaAssetManifestEntry(
      file: json['file']?.toString() ?? '',
      src: json['src']?.toString() ?? '',
      css: _stringList(json['css']),
      assets: _stringList(json['assets']),
      imports: _stringList(json['imports']),
      isEntry: json['isEntry'] == true,
    );
  }

  /// The built file path produced by Vite.
  final String file;

  /// The source entry path.
  final String src;

  /// The CSS files associated with this entry.
  final List<String> css;

  /// Additional assets referenced by this entry.
  final List<String> assets;

  /// Imported entry keys.
  final List<String> imports;

  /// Whether this entry is a top-level entry point.
  final bool isEntry;
}

/// Converts a JSON value into a list of strings.
List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}
