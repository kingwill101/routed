import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

final _repository = NewsletterRepository(DatabaseService.instance);

/// Newsletter subscription API view
class NewsletterView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST', 'DELETE'];

  @override
  Future<void> get() async {
    // Check if this is the stats endpoint
    if ((await getUri()).path.endsWith('/stats')) {
      await getStats();
      return;
    }

    // Return API information for newsletter subscriptions
    final stats = await _repository.getStats();

    sendJson({
      'message': 'Newsletter subscription API',
      'form_action': (await getUri()).path,
      'form_method': 'POST',
      'required_fields': ['email'],
      'optional_fields': ['name'],
      'stats': stats,
      'example': {'email': 'user@example.com', 'name': 'John Doe'},
      'validation': {
        'email': 'Required, must be a valid email address',
        'name': 'Optional, subscriber name',
      },
      'endpoints': {
        'subscribe': 'POST /api/newsletter',
        'unsubscribe': 'DELETE /api/newsletter/<email>',
        'stats': 'GET /api/newsletter/stats',
      },
    });
  }

  @override
  Future<void> post() async {
    try {
      final data = await getJsonBody();

      // Validate required fields
      final email = data['email'] as String?;
      if (email == null || email.trim().isEmpty) {
        throw ArgumentError('Email is required and cannot be empty');
      }

      // Basic email validation
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email.trim())) {
        throw ArgumentError('Please provide a valid email address');
      }

      final name = data['name'] as String?;

      // Create subscription (repository handles duplicates)
      final subscription = await _repository.create(
        email.trim().toLowerCase(),
        name: name?.trim().isNotEmpty == true ? name!.trim() : null,
      );

      sendJson({
        'success': true,
        'subscription': subscription.toJson(),
        'message': 'Successfully subscribed to newsletter!',
      }, statusCode: 201);
    } catch (error) {
      await _handleError(error);
    }
  }

  @override
  Future<void> delete() async {
    // Get email parameter from URL
    final email = await getParam('email');
    if (email == null || email.trim().isEmpty) {
      sendJson({
        'success': false,
        'error': 'Email parameter is required',
      }, statusCode: 400);
      return;
    }

    await unsubscribe(email);
  }

  /// Get newsletter subscription statistics
  Future<void> getStats() async {
    try {
      final stats = await _repository.getStats();
      final subscriptions = await _repository.findAll(activeOnly: false);

      sendJson({
        'stats': stats,
        'recent_subscriptions': subscriptions
            .take(5)
            .map(
              (s) => {
                'email': s.email,
                'name': s.name,
                'subscribed_at': s.subscribedAt.toIso8601String(),
                'is_active': s.isActive,
              },
            )
            .toList(),
      });
    } catch (error) {
      await _handleError(error);
    }
  }

  /// Unsubscribe by email
  Future<void> unsubscribe(String email) async {
    try {
      final success = await _repository.unsubscribeByEmail(email.toLowerCase());

      if (success) {
        sendJson({
          'success': true,
          'message': 'Successfully unsubscribed from newsletter',
          'email': email,
        });
      } else {
        sendJson({
          'success': false,
          'error': 'Email address not found in subscription list',
          'email': email,
        }, statusCode: 404);
      }
    } catch (error) {
      await _handleError(error);
    }
  }

  /// Handle errors with appropriate status codes
  Future<void> _handleError(Object error) async {
    int statusCode = 400;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    } else if (error is ArgumentError) {
      statusCode = 400;
      message = error.message;
    } else if (error.toString().contains('already subscribed')) {
      statusCode = 409; // Conflict
      message = 'This email address is already subscribed to the newsletter';
    } else {
      statusCode = 500;
      message =
          'An unexpected error occurred while processing your subscription';
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }
}
