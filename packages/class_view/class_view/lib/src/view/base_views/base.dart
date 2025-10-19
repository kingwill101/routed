import 'dart:async';
import 'dart:io' show HttpStatus;

import '../exceptions/http.dart';
import '../form/renderer.dart';
import '../mixins/view_mixin.dart';

/// Base view class providing core functionality
///
/// All views inherit from this class and have access to:
/// - Request/response handling via ViewMixin
/// - Template rendering via Renderer
/// - Form integration with unified rendering
abstract class View with ViewMixin {
  /// Optional renderer for this view instance
  Renderer? _renderer;

  /// Set a renderer for this view
  ///
  /// This allows using any Renderer implementation:
  /// ```dart
  /// view.setRenderer(TemplateRenderer(viewEngine));
  /// view.setRenderer(CustomRenderer());
  /// ```
  /// Forms and widgets will use this renderer directly.
  void setRenderer(Renderer renderer) {
    _renderer = renderer;
  }

  /// Get the renderer for forms and widgets
  ///
  /// This is what forms should use: `Form(renderer: view.renderer, ...)`
  /// Returns null if no rendering system is configured (will use DefaultView fallbacks).
  Renderer? get renderer => _renderer;

  /// Handle errors that occur during request processing
  @override
  Future<void> handleError(Object error, [StackTrace? stackTrace]) async {
    int statusCode = HttpStatus.internalServerError;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    }

    await sendJson({'error': message}, statusCode: statusCode);
  }

  /// Handle GET requests
  @override
  Future<void> get() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle POST requests
  @override
  Future<void> post() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle PUT requests
  @override
  Future<void> put() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle DELETE requests
  @override
  Future<void> delete() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle PATCH requests
  @override
  Future<void> patch() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle HEAD requests
  @override
  Future<void> head() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Handle OPTIONS requests
  @override
  Future<void> options() async {
    throw HttpException.methodNotAllowed(
      message: 'Method not allowed',
      allowedMethods: allowedMethods,
    );
  }

  /// Dispatch the request to the appropriate method handler
  @override
  Future<void> dispatch() async {
    try {
      await setup();
      await beforeDispatch();

      final requestMethod = await getMethod();

      if (!allowedMethods.contains(requestMethod)) {
        throw HttpException.methodNotAllowed(
          message: 'Method not allowed',
          allowedMethods: allowedMethods,
        );
      }

      switch (requestMethod) {
        case 'GET':
          await get();
          break;
        case 'POST':
          await post();
          break;
        case 'PUT':
          await put();
          break;
        case 'DELETE':
          await delete();
          break;
        case 'PATCH':
          await patch();
          break;
        case 'HEAD':
          await head();
          break;
        case 'OPTIONS':
          await options();
          break;
        default:
          throw HttpException.methodNotAllowed(
            message: 'Method not allowed',
            allowedMethods: allowedMethods,
          );
      }

      await afterDispatch();
    } catch (e, stackTrace) {
      await handleError(e, stackTrace);
    } finally {
      await teardown();
    }
  }
}
