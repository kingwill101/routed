import 'package:path/path.dart' as path;

import 'view_engine.dart';

/// Manages multiple view engines and delegates rendering to the appropriate one
class ViewEngineManager {
  final Map<String, ViewEngine> _engines = {};

  /// Register a view engine
  void register(ViewEngine engine) {
    for (final ext in engine.extensions) {
      _engines[ext] = engine;
    }
  }

  /// Get the appropriate engine for a file extension
  ViewEngine? engineForFile(String filePath) {
    final ext = path.extension(filePath);
    return _engines[ext];
  }

  /// Render a template file using the appropriate view engine
  ///
  /// [filePath] The path to the template file to render
  /// [data] Optional data to pass to the template rendering process
  ///
  /// Returns the rendered template as a [Future<String>]
  Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    final engine = engineForFile(filePath);
    if (engine == null) {
      throw Exception(
        'No view engine registered for ${path.extension(filePath)}',
      );
    }
    return engine.renderFile(filePath, data);
  }

  /// Render template content using the appropriate view engine
  ///
  /// Attempts to find a registered view engine based on the content's file extension.
  /// Throws an exception if no matching view engine is found.
  ///
  /// [content] The template content or file path to render
  /// [data] Optional data to pass to the template rendering process
  ///
  /// Returns the rendered template as a [Future<String>]
  Future<String> render(String content, [Map<String, dynamic>? data]) async {
    final engine = engineForFile(content);
    if (engine == null) {
      throw Exception(
        'No view engine registered for ${path.extension(content)}',
      );
    }
    return engine.render(content, data);
  }
}
