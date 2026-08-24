/// Base interface for all view engines.
///
/// A view engine is responsible for rendering templates using a specific
/// templating language or format. Each view engine implementation must provide
/// methods for loading templates, adding custom functions and filters, and
/// rendering templates with data.
///
/// Reserved data key used to pass an `EngineContext` to a view engine.
const String kViewEngineContextKey = '__routed_context';

/// Contract implemented by every template rendering engine.
abstract class ViewEngine {
  /// The file extensions this engine handles, such as `.liquid` or `.jinja`.
  List<String> get extensions;

  /// Renders a template with the given [name] and [data].
  ///
  /// Returns the rendered template as a string.
  /// Throws a [TemplateNotFoundException] if the template doesn't exist.
  Future<String> render(String name, [Map<String, dynamic>? data]);

  /// Renders a template file with the given data.
  ///
  /// Similar to [render], but loads the template from a file at [filePath]
  /// instead of using a pre-loaded template.
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]);
}

/// Exception thrown when a template cannot be found.
class TemplateNotFoundException implements Exception {
  /// Creates an exception for a missing [templateName].
  TemplateNotFoundException(this.templateName)
    : message = 'Template not found: $templateName';

  /// Name of the template that could not be found.
  final String templateName;

  /// Human-readable explanation of the missing template.
  final String message;

  @override
  String toString() => message;
}
