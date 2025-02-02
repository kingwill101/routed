import 'dart:io' show HttpStatus;

import 'package:routed/src/render/html/template_engine.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// The `HTMLRender` class is responsible for rendering HTML content using a specified template and data.
/// It implements the `Render` interface.
class HTMLRender implements Render {
  /// The name of the template to be used for rendering.
  final String templateName;

  /// The data to be passed to the template for rendering.
  final Map<String, dynamic> data;

  /// The template engine used to render the HTML content.
  final TemplateEngine engine;

  /// Constructs an instance of `HTMLRender`.
  ///
  /// The [templateName] parameter specifies the name of the template to be used.
  /// The [data] parameter provides the data to be passed to the template.
  /// The [engine] parameter specifies the template engine to be used for rendering.
  HTMLRender({
    required this.templateName,
    required this.data,
    required this.engine,
  });

  /// Renders the HTML content and writes it to the [response].
  ///
  /// This method sets the content type of the response to 'text/html; charset=utf-8'.
  /// It then attempts to render the content using the specified template and data.
  /// If an error occurs during rendering, it sets the response status code to 500 (Internal Server Error)
  /// and writes an error message to the response.
  ///
  /// The [response] parameter is the response object where the rendered content will be written.
  @override
  Future<void> render(Response response) async {
    writeContentType(response);
    try {
      String content = await engine.render(templateName, data);
      response.write(content);
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('Error rendering template: $e');
    }
  }

  /// Sets the content type of the [response] to 'text/html; charset=utf-8'.
  ///
  /// This method is called before rendering the content to ensure that the response
  /// has the correct content type for HTML.
  ///
  /// The [response] parameter is the response object where the content type will be set.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'text/html; charset=utf-8');
  }
}
