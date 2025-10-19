import '../adapter/view_adapter.dart';
import '../view/base_views/base.dart';

/// Laravel-style response object for fluent response building
///
/// Provides a clean, expressive API for building different types of responses:
/// - HTML responses for Django-style forms
/// - JSON responses for APIs
/// - Template/view rendering integrated with view's rendering system
/// - Redirects
/// - Plain text responses
///
/// Now integrates with the view's ViewEngine/Renderer system and includes
/// DefaultView fallback for graceful degradation.
class Response {
  final ViewAdapter _adapter;
  final View? _view;

  Response(this._adapter, [this._view]);

  /// Send HTML response
  ///
  /// Perfect for Django-style form rendering:
  /// ```dart
  /// response().html({@literal '<form>...</form>'});
  /// ```
  Response html(String html, {int statusCode = 200}) {
    _adapter.setStatusCode(statusCode);
    _adapter.setHeader('Content-Type', 'text/html; charset=utf-8');
    _adapter.write(html);
    return this;
  }

  /// Send JSON response
  ///
  /// For API endpoints:
  /// ```dart
  /// response().json({'data': posts});
  /// ```
  Response json(Map<String, dynamic> data, {int statusCode = 200}) {
    _adapter.writeJson(data, statusCode: statusCode);
    return this;
  }

  /// View method - Render template with ViewEngine/Renderer
  ///
  /// This is the primary way to render views with templates:
  /// ```dart
  /// response().view('user/profile.html', {'user': user});
  /// ```
  ///
  /// Throws exception if no renderer is configured or rendering fails.
  Future<Response> view(
    String template, [
    Map<String, dynamic>? context,
  ]) async {
    context ??= {};

    // Try to use the view's renderer
    final renderer = _view?.renderer;
    if (renderer == null) {
      throw StateError(
        'No renderer configured. Use view.setRenderer() or view.setViewEngine()',
      );
    }

    try {
      final html = await renderer.renderAsync(template, context);
      return this.html(html);
    } catch (e) {
      throw Exception('Template rendering failed: $template. Error: $e');
    }
  }

  /// Send plain text response
  ///
  /// For simple text responses:
  /// ```dart
  /// response().text('Hello World');
  /// ```
  Response text(String text, {int statusCode = 200}) {
    _adapter.setStatusCode(statusCode);
    _adapter.setHeader('Content-Type', 'text/plain; charset=utf-8');
    _adapter.write(text);
    return this;
  }

  /// Redirect response
  ///
  /// After form submission success:
  /// ```dart
  /// response().redirect('/posts/1');
  /// ```
  Response redirect(String url, {int statusCode = 302}) {
    _adapter.redirect(url, statusCode: statusCode);
    return this;
  }

  /// Set headers fluently
  ///
  /// Chain headers for clean syntax:
  /// ```dart
  /// response()
  ///   .header('Cache-Control', 'max-age=3600')
  ///   .html(content);
  /// ```
  Response header(String name, String value) {
    _adapter.setHeader(name, value);
    return this;
  }

  /// Set status code fluently
  ///
  /// Set status before response:
  /// ```dart
  /// response()
  ///   .status(422)
  ///   .view('form.html', {'errors': errors});
  /// ```
  Response status(int code) {
    _adapter.setStatusCode(code);
    return this;
  }
}
