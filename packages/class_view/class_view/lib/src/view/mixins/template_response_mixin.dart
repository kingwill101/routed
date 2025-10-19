import 'dart:async';
import 'dart:io' show HttpStatus;

import 'package:class_view/class_view.dart';

/// Exception thrown when a template name is not configured
class ImproperlyConfigured implements Exception {
  final String message;

  ImproperlyConfigured(this.message);

  @override
  String toString() => message;
}

/// Mixin that provides template response functionality similar to Django
mixin TemplateResponseMixin on ViewMixin {
  ViewEngine? get viewEngine => TemplateManager.engine;

  /// The template name to use for rendering
  String? get templateName;

  /// The content type for the response
  String get contentType => 'text/html';

  List<String> get extensions => ['html', 'htm'];

  /// Renders the template to a response using the provided context and optional template name
  ///
  /// [templateContext] A map of additional context variables for template rendering
  /// [templateName] Optional custom template name to override the default [templateName]
  ///
  /// Throws [UnimplementedError] if the method is not implemented in the subclass
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = HttpStatus.ok,
  }) async {
    final engine = viewEngine;
    if (engine == null) {
      throw ImproperlyConfigured('View engine is not configured');
    }

    final templateNames = await getTemplateNames();
    if (templateNames.isEmpty) {
      throw ImproperlyConfigured('No template names available');
    }

    // Process the template context before rendering
    final processedContext = await processTemplateContext(templateContext);

    // Render the template using the view engine
    final content = await engine.render(templateNames.first, processedContext);

    // Set response headers and content
    await setHeader('Content-Type', contentType);
    await setStatusCode(statusCode);
    await write(content);
  }

  /// Process the template context before rendering
  Future<Map<String, dynamic>> processTemplateContext(
    Map<String, dynamic> context,
  ) async {
    return context;
  }

  /// Returns a list of template names to be searched for
  Future<List<String>> getTemplateNames() async {
    if (templateName == null) {
      return [];
    }

    // Support template name patterns with extensions
    final name = templateName!;
    if (!name.contains('.')) {
      return [...extensions.map((ext) => '$name.$ext'), name];
    }
    return [name];
  }
}
