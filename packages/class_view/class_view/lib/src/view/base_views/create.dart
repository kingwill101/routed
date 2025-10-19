import 'dart:async';

import '../mixins/context_mixin.dart';
import '../mixins/success_url_mixin.dart';
import 'base.dart';

/// A generic view that handles object creation for APIs
///
/// Users implement a single method and get full creation functionality.
/// Works with any response format - JSON, HTML, XML, text, etc.
/// Mixins work behind the scenes as internal building blocks.
///
/// ## Usage
///
/// ```dart
/// class PostCreateView extends CreateView<Post> {
///   @override
///   Future<Post> performCreate(Map<String, dynamic> data) async {
///     return Post.fromJson(data);
///   }
///
///   @override
///   String get successUrl => '/posts';  // Optional redirect
/// }
/// ```
///
/// ## What You Get
///
/// - GET requests return context data (for form display, etc.)
/// - POST requests process data and create objects
/// - Automatic success/failure handling with flexible responses
/// - Support for JSON, form data, and other content types
/// - Framework-agnostic API patterns
abstract class CreateView<T> extends View
    with ContextMixin, SuccessFailureUrlMixin {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  /// Create and return the object - the only method users need to implement
  ///
  /// This method receives processed request data and should create the object
  /// in your data store (database, API, etc.).
  ///
  /// [data] - The processed request data for creating the object
  /// Returns the created object of type T
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<Post> performCreate(Map<String, dynamic> data) async {
  ///   final post = Post.fromJson(data);
  ///   return await PostRepository.save(post);
  /// }
  /// ```
  Future<T> performCreate(Map<String, dynamic> data);

  /// Get data from the request based on content type
  Future<Map<String, dynamic>> getRequestData() async {
    final method = await getMethod();
    if (method == 'POST') {
      final contentType = await getHeader('content-type') ?? '';
      if (contentType.contains('application/json')) {
        return await getJsonBody();
      } else {
        return await getFormData();
      }
    }
    return {};
  }

  /// Process the creation request with error handling
  Future<void> process(Map<String, dynamic> data) async {
    final object = await performCreate(data);
    await onSuccess(object);
  }

  @override
  Future<void> get() async {
    // Return context data - could be used for form display, API schema, etc.
    final contextData = await getContextData();
    final uri = await getUri();

    // Add metadata that might be useful for forms or API clients
    final responseData = {
      ...contextData,
      'create_url': uri.path,
      'method': 'POST',
      'form': {'is_bound': false}, // Ensure form is not bound for GET requests
    };

    // Default to JSON response, but users can override this method for different formats
    await sendJson(responseData);
  }

  @override
  Future<void> post() async {
    try {
      final data = await getRequestData();
      await process(data);
    } catch (e) {
      await onFailure(e);
    }
  }
}
