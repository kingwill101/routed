import 'package:path/path.dart' as path;

import 'package:routed_views/src/view/view_engine.dart';

/// Selects a view engine from a template's file extension.
///
/// Register each engine before handling requests. When more than one engine
/// claims the same extension, the most recently registered engine wins. The
/// manager does not load files or catch engine failures; it only performs
/// extension dispatch and delegates the render operation.
class ViewEngineManager {
  final Map<String, ViewEngine> _engines = {};

  /// Registers [engine] for every extension in [ViewEngine.extensions].
  ///
  /// Extensions should include their leading dot. Registering an extension a
  /// second time replaces the previous mapping, which makes this method useful
  /// for application-level overrides of provider defaults.
  void register(ViewEngine engine) {
    for (final ext in engine.extensions) {
      _engines[ext] = engine;
    }
  }

  /// Returns the engine registered for [filePath]'s extension.
  ///
  /// Returns `null` when the path has no extension or no engine claims that
  /// extension. The path itself is not normalized or checked for existence.
  ViewEngine? engineForFile(String filePath) {
    final ext = path.extension(filePath);
    return _engines[ext];
  }

  /// Renders the file at [filePath] through its registered engine.
  ///
  /// [data] is passed unchanged to the selected engine. The manager does not
  /// check that the file exists; file loading and template failures are
  /// reported by the engine.
  ///
  /// Throws an [Exception] if no engine is registered for the file extension,
  /// or rethrows an exception raised while rendering the file.
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

  /// Renders in-memory [content] through its registered engine.
  ///
  /// The manager selects an engine from [path.extension] of [content] and
  /// passes the complete string to [ViewEngine.render]. This dispatch shape is
  /// intended for engines whose inline source also carries a recognizable
  /// suffix; use [renderFile] for ordinary named template files. If the
  /// content has no registered suffix, this method throws before rendering.
  /// Exceptions from the selected engine are propagated to the caller.
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
