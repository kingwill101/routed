/// Reserved data key used to pass an `EngineContext` to a view engine.
///
/// When a request is rendered through `EngineContext.template`, Routed adds
/// the current context to the data map under this key. Engines that understand
/// request-aware helpers should consume that reserved entry before exposing
/// the remaining values to a template.
const String kViewEngineContextKey = '__routed_context';

/// Contract implemented by a template rendering engine.
///
/// A view engine owns the syntax and loading rules for one template format.
/// Implementations declare the file extensions they accept, render in-memory
/// template sources, and render files from a configured file system.
///
/// A view engine is normally registered with `ViewEngineManager`, or supplied
/// directly through the typed view provider configuration. The built-in
/// `LiquidViewEngine` is the default engine, but custom implementations can
/// support any template language.
abstract class ViewEngine {
  /// File extensions handled by this engine.
  ///
  /// Each extension should include its leading dot, for example `.liquid` or
  /// `.jinja`. `ViewEngineManager` compares these values with the extension
  /// returned for a template path, so an implementation should use the same
  /// casing it expects to receive from callers.
  List<String> get extensions;

  /// Renders an in-memory template source with [data].
  ///
  /// [name] is the engine-specific source or identifier. For a file-backed
  /// template, use [renderFile] so the implementation can apply its file
  /// loading and path rules. The returned string contains the rendered output.
  ///
  /// Implementations may throw [TemplateNotFoundException] or an engine-
  /// specific rendering exception when parsing, loading, or evaluating the
  /// source fails. Callers should not assume that a failed render produces a
  /// partial response.
  Future<String> render(String name, [Map<String, dynamic>? data]);

  /// Loads and renders the template file at [filePath] with [data].
  ///
  /// [filePath] is passed to the engine's file-loading implementation. A
  /// relative path may be resolved against the engine's configured template
  /// directory; an absolute path is implementation-defined but is commonly
  /// used as-is. Missing files and file-system failures are reported by the
  /// implementation, commonly as [TemplateNotFoundException] or a rendering
  /// exception.
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]);
}

/// Exception thrown when a template cannot be found.
class TemplateNotFoundException implements Exception {
  /// Creates an exception for the missing [templateName].
  TemplateNotFoundException(this.templateName)
    : message = 'Template not found: $templateName';

  /// Name of the template that could not be found.
  final String templateName;

  /// Human-readable explanation of the missing template.
  final String message;

  /// Returns [message] for logs and error responses.
  @override
  String toString() => message;
}
