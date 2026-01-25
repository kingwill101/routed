/// Represents resolved Vite asset tags for rendering.
///
/// ```dart
/// final tags = await assets.resolve();
/// final html = tags.renderAll();
/// ```
class InertiaViteAssetTags {
  /// Creates a tag bundle for scripts and styles.
  const InertiaViteAssetTags({
    this.scripts = const [],
    this.styles = const [],
    this.devServerUrl,
  });

  /// The script tags to render.
  final List<String> scripts;

  /// The style tags to render.
  final List<String> styles;

  /// The dev server URL, if running in dev mode.
  final String? devServerUrl;

  /// Renders script tags into a single HTML string.
  String renderScripts() => scripts.join('\n');

  /// Renders style tags into a single HTML string.
  String renderStyles() => styles.join('\n');

  /// Renders styles and scripts into a single HTML string.
  String renderAll() => [...styles, ...scripts].join('\n');
}
