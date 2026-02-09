/// Represents resolved assets for a manifest entry.
///
/// ```dart
/// final resolution = manifest.resolve('index.html');
/// ```
class InertiaAssetResolution {
  /// Creates an asset resolution result.
  const InertiaAssetResolution({
    required this.file,
    required this.css,
    required this.imports,
    required this.assets,
  });

  /// The main JavaScript file, if any.
  final String? file;

  /// The resolved CSS files.
  final List<String> css;

  /// The resolved import files.
  final List<String> imports;

  /// The resolved static assets.
  final List<String> assets;
}
