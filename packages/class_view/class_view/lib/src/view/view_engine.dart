/// Base interface for all view engines.
///
/// A view engine is responsible for rendering templates using a specific
/// templating language or format. Each view engine implementation must provide
/// methods for loading templates, adding custom functions and filters, and
/// rendering templates with data.
abstract class ViewEngine {
  /// The file extensions this engine handles (e.g. ['.liquid', '.jinja'])
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
  final String templateName;
  final String message;

  TemplateNotFoundException(this.templateName)
    : message = 'Template not found: $templateName';

  @override
  String toString() => message;
}
