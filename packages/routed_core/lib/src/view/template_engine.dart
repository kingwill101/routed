abstract class TemplateEngine {
  /// Renders a template with the given name using the provided data.
  ///
  /// [templateName] is the name of the template to be rendered.
  /// [data] is a map containing key-value pairs that will be used to populate the template.
  /// Returns a [Future] that completes with the rendered template as a [String].
  Future<String> render(
    String templateName, [
    Map<String, dynamic> data = const {},
  ]);

  String renderContent(String content, [Map<String, dynamic> data = const {}]);

  /// Loads templates from the specified path.
  ///
  /// [path] is the directory path where the templates are located.
  /// This method should be called before attempting to render any templates.
  void loadTemplates(String path);

  Map<String, Function> get funcMap;

  Map<String, Function> get filterMap;

  void addFunc(String name, Function fn);

  void addFilter(String name, Function filter);
}
