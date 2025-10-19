import 'media.dart';
import 'media_defining_class.dart';

/// A widget for including JavaScript files
class Script implements MediaDefiningClass {
  /// The path to the JavaScript file
  final String path;

  /// Whether this is an external URL
  final bool isExternal;

  /// Additional attributes for the script tag
  final Map<String, String> attrs;

  const Script({
    required this.path,
    this.isExternal = false,
    this.attrs = const {},
  });

  @override
  List<Media> getMedia() {
    return [Media.js(path, isExternal: isExternal, attrs: attrs)];
  }
}
