/// Represents a media file (CSS, JavaScript, etc.)
class Media {
  /// The path to the media file
  final String path;

  /// The type of media (js, css)
  final String type;

  /// Whether this is an external URL
  final bool isExternal;

  /// Additional attributes for the media tag
  final Map<String, String> attrs;

  const Media({
    required this.path,
    required this.type,
    this.isExternal = false,
    this.attrs = const {},
  });

  /// Create a JavaScript media file
  factory Media.js(
    String path, {
    bool isExternal = false,
    Map<String, String> attrs = const {},
  }) {
    return Media(path: path, type: 'js', isExternal: isExternal, attrs: attrs);
  }

  /// Create a CSS media file
  factory Media.css(
    String path, {
    bool isExternal = false,
    Map<String, String> attrs = const {},
  }) {
    return Media(path: path, type: 'css', isExternal: isExternal, attrs: attrs);
  }

  /// Render this media file as HTML
  String render() {
    final attrsStr = attrs.entries
        .map((e) => '${e.key}="${e.value}"')
        .join(' ');

    switch (type) {
      case 'js':
        return '<script src="$path" $attrsStr></script>';
      case 'css':
        return '<link rel="stylesheet" href="$path" $attrsStr />';
      default:
        return '';
    }
  }
}
