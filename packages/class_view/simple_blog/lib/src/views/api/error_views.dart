import 'package:class_view/class_view.dart';

/// Custom error views demonstrating error handling patterns
///
/// Shows how to create custom error pages that:
/// - Provide helpful error information
/// - Match your application style
/// - Log errors appropriately
/// - Guide users to recovery

/// Custom 404 Not Found view
class NotFoundView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final path = await getParam('path') ?? 'unknown';

    sendJson({
      'error': 'Not Found',
      'status': 404,
      'message': 'The requested resource was not found',
      'path': path,
      'suggestions': _getSuggestions(path),
    }, statusCode: 404);
  }

  List<String> _getSuggestions(String path) {
    // Provide helpful suggestions based on the requested path
    if (path.contains('/posts/')) {
      return ['/api/posts - List all posts', '/posts/new - Create a new post'];
    }
    if (path.contains('/comments/')) {
      return ['/api/comments - List all comments'];
    }
    return ['/ - Home page', '/api/posts - Browse posts'];
  }
}

/// Custom 500 Internal Server Error view
class ServerErrorView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final errorMsg = await getParam('error') ?? 'An unexpected error occurred';

    // In production, don't expose error details
    final isDevelopment = true; // TODO: Get from environment

    sendJson({
      'error': 'Internal Server Error',
      'status': 500,
      'message': isDevelopment
          ? errorMsg
          : 'An unexpected error occurred. Please try again later.',
      'support': 'Contact support@example.com for assistance',
    }, statusCode: 500);
  }
}

/// Custom 403 Forbidden view
class ForbiddenView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final resource = await getParam('resource') ?? 'this resource';

    sendJson({
      'error': 'Forbidden',
      'status': 403,
      'message': 'You do not have permission to access $resource',
      'action': 'Please log in or contact an administrator',
    }, statusCode: 403);
  }
}

/// Custom 400 Bad Request view
class BadRequestView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final reason = await getParam('reason') ?? 'Invalid request';

    sendJson({
      'error': 'Bad Request',
      'status': 400,
      'message': reason,
      'help': 'Check the API documentation for correct request format',
    }, statusCode: 400);
  }
}

/// Validation error view for form submissions
class ValidationErrorView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  Future<void> get() async {
    await post();
  }

  @override
  Future<void> post() async {
    // This would typically be called with validation error details
    sendJson({
      'error': 'Validation Error',
      'status': 422,
      'message': 'The submitted data did not pass validation',
      'errors': {
        'example_field': ['This field is required'],
      },
    }, statusCode: 422);
  }
}
