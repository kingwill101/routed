import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../forms/newsletter.dart';
import '../../repositories/newsletter_repository.dart';
import '../../repositories/post_repository.dart';

/// Web home view with newsletter signup form
/// Uses template-first approach - automatically renders HTML templates
class WebHomeView extends BaseFormView {
  late final PostRepository _repository;
  late final NewsletterRepository _newsletterRepository;

  WebHomeView() {
    _repository = PostRepository(DatabaseService.instance);
    _newsletterRepository = NewsletterRepository(DatabaseService.instance);
  }

  @override
  String get templateName => 'base/home.liquid';

  @override
  Form getForm([Map<String, dynamic>? data]) =>
      NewsletterForm(data: data, isBound: data != null);

  @override
  Future<void> formValid(Form form) async {
    final newsletterForm = form as NewsletterForm;
    final cleanedData = newsletterForm.cleanedData;

    try {
      // Extract email and name from the form
      final email = cleanedData['email'] as String;
      final name = cleanedData['name'] as String?;

      // Save the subscription to the database
      final subscription = await _newsletterRepository.create(
        email,
        name: name,
      );

      print('Newsletter subscription created: ${subscription.email}');

      // Redirect with success message
      redirect('/?newsletter_success=true');
    } catch (e) {
      print('Newsletter subscription error: $e');

      // Handle the case where email is already subscribed
      if (e.toString().contains('already subscribed')) {
        redirect('/?newsletter_error=already_subscribed');
      } else {
        redirect('/?newsletter_error=general');
      }
    }
  }

  @override
  Future<void> formInvalid(Form form) async {
    // Don't redirect on validation errors - let the template show the errors
    print('Form is invalid! Errors: ${form.errors}'); // Debug output

    final contextData = await getContextData();
    contextData['form'] = form; // Include the invalid form with field errors

    // Add some debug info
    print('Form field errors:');
    for (final fieldName in form.fields.keys) {
      final boundField = form[fieldName];
      if (boundField.hasErrors) {
        print('  $fieldName: ${boundField.errors}');
      }
    }

    await renderToResponse(contextData, statusCode: 400);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final recentPosts = await _repository.findAll(publishedOnly: true);
    final totalPosts = await _repository.findAll();

    // Check for newsletter status messages
    final newsletterSuccess = await getParam('newsletter_success');
    final newsletterError = await getParam('newsletter_error');

    String? successMessage;
    String? errorMessage;

    if (newsletterSuccess == 'true') {
      successMessage = '🎉 Thank you for subscribing to our newsletter!';
    }

    if (newsletterError == 'already_subscribed') {
      errorMessage =
          '📧 This email address is already subscribed to our newsletter.';
    } else if (newsletterError == 'general') {
      errorMessage =
          '❌ There was an error processing your subscription. Please try again.';
    }

    return {
      'page_title': 'SimpleBlog - Showcasing Class View Features',
      'page_description':
          'A demonstration blog built with Dart class_view framework',
      'recent_posts': recentPosts.take(3).map((p) => p.toJson()).toList(),
      'total_posts': totalPosts.length,
      'published_posts': recentPosts.length,
      'features': _getFeatures(),
      'success_message': successMessage,
      'error_message': errorMessage,
    };
  }

  /// Get the features list for the home page
  List<Map<String, dynamic>> _getFeatures() {
    return [
      {
        'title': 'Template-First Design',
        'description':
            'Beautiful HTML forms and pages by default, JSON APIs when needed',
        'icon': '🎨',
      },
      {
        'title': 'Full CRUD Operations',
        'description':
            'Complete Create, Read, Update, Delete functionality using class_view',
        'icon': '✅',
      },
      {
        'title': 'Django-style Views',
        'description':
            'Clean, composable views with mixins for maximum flexibility',
        'icon': '🏗️',
      },
      {
        'title': 'Search & Pagination',
        'description':
            'Built-in search functionality with efficient pagination',
        'icon': '🔍',
      },
      {
        'title': 'Form Validation',
        'description':
            'Robust form handling with validation and error management',
        'icon': '📝',
      },
      {
        'title': 'RESTful API',
        'description': 'JSON API endpoints that work seamlessly with the views',
        'icon': '🌐',
      },
    ];
  }
}
