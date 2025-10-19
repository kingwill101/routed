/// Base class for form renderers.
///
/// A renderer is responsible for loading and rendering templates for forms
/// and formsets. Subclasses can customize the template loading and rendering
/// process.
abstract class Renderer {
  /// Template name for rendering forms.
  final String formTemplateName;

  /// Template name for rendering formsets.
  final String formsetTemplateName;

  /// Template name for rendering fields.
  final String fieldTemplateName;

  /// The bound field class to use.
  final Type? boundFieldClass = null;

  Renderer({
    this.formTemplateName = 'form/div.html',
    this.formsetTemplateName = 'form/formsets/div.html',
    this.fieldTemplateName = 'form/field.html',
  });

  /// Gets a template by name.
  ///
  /// Subclasses must implement this to return the appropriate template.
  Template getTemplate(String templateName) {
    throw UnimplementedError('subclasses must implement get_template()');
  }

  /// Renders a template with the given context synchronously.
  ///
  /// [templateName] is the name of the template to render.
  /// [context] contains the data to pass to the template.
  /// [request] is an optional HTTP request object that may be used during rendering.
  ///
  /// Returns the rendered template as a string with whitespace trimmed.
  String renderSync(
    String templateName,
    Map<String, dynamic> context, [
    dynamic extra1,
  ]) {
    final template = getTemplate(templateName);
    return template.render(context, extra1).trim();
  }

  /// Renders a template with the given context asynchronously.
  ///
  /// [templateName] is the name of the template to render.
  /// [context] contains the data to pass to the template.
  ///
  /// Returns a Future that completes with the rendered template as a string.
  Future<String> renderAsync(String templateName, Map<String, dynamic> context);
}

class RenderException implements Exception {
  final String message;

  RenderException(this.message);

  @override
  String toString() {
    return 'RenderException: $message';
  }
}

abstract class Template {
  String render(Map<String, dynamic> context, [dynamic extra1]);
}
