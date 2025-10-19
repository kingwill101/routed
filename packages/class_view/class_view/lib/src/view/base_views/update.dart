import '../mixins/context_mixin.dart';
import '../mixins/single_object_mixin.dart';
import '../mixins/success_url_mixin.dart';
import 'base.dart';

/// A generic view for updating an existing object for APIs
///
/// Users implement two methods and get full update functionality.
/// Works with any response format - JSON, HTML, XML, text, etc.
/// Mixins work behind the scenes as internal building blocks.
///
/// ## Usage
///
/// ```dart
/// class PostUpdateView extends UpdateView<Post> {
///   @override
///   Future<Post?> getObject() async {
///     final id = await getParam('id');
///     return await PostRepository.findById(id);
///   }
///
///   @override
///   Future<Post> performUpdate(Post post, Map<String, dynamic> data) async {
///     return await PostRepository.update(post.id, data);
///   }
///
///   @override
///   String get successUrl => '/posts';  // Optional redirect
/// }
/// ```
///
/// ## What You Get
///
/// - GET requests return object data and context
/// - PUT/PATCH requests process updates and save changes
/// - Automatic 404 handling if object not found
/// - Automatic success/failure handling
/// - Support for JSON, form data, and other content types
/// - Framework-agnostic API patterns
abstract class UpdateView<T> extends View
    with ContextMixin, SingleObjectMixin<T>, SuccessFailureUrlMixin {
  @override
  List<String> get allowedMethods => ['GET', 'PUT', 'PATCH'];

  /// Get the object to update - one of two methods users need to implement
  ///
  /// This method should fetch the object from your data store.
  /// Return null if the object is not found (will result in 404).
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<Post?> getObject() async {
  ///   final id = await getParam('id');
  ///   return await PostRepository.findById(id);
  /// }
  /// ```
  @override
  Future<T?> getObject();

  /// Update the object with provided data - the other method users need to implement
  ///
  /// This method receives the existing object and update data, then should
  /// save the changes to your data store.
  ///
  /// [object] - The existing object to update
  /// [data] - The processed request data for updating the object
  /// Returns the updated object of type T
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<Post> performUpdate(Post post, Map<String, dynamic> data) async {
  ///   final updated = post.copyWith(
  ///     title: data['title'],
  ///     content: data['content'],
  ///   );
  ///   return await PostRepository.save(updated);
  /// }
  /// ```
  Future<T> performUpdate(T object, Map<String, dynamic> data);

  /// Get data from the request based on content type
  Future<Map<String, dynamic>> getRequestData() async {
    final method = await getMethod();
    if (method == 'PUT' || method == 'PATCH') {
      final contentType = await getHeader('content-type') ?? '';
      if (contentType.contains('application/json')) {
        return await getJsonBody();
      } else {
        return await getFormData();
      }
    }
    return {};
  }

  /// Process the update request with error handling
  Future<void> process(Map<String, dynamic> data) async {
    final object = await getObjectOr404();
    final updated = await performUpdate(object, data);
    await onSuccess(updated);
  }

  @override
  Future<void> get() async {
    // Return object data and context for GET requests
    final contextData = await getContextData();
    final uri = await getUri();
    final responseData = {
      ...contextData,
      'update_url': uri.path,
      'method': 'PUT',
    };
    // Default to JSON response, but users can override for different formats
    await sendJson(responseData);
  }

  @override
  Future<void> put() async => await _handleUpdate();

  @override
  Future<void> patch() async => await _handleUpdate();

  Future<void> _handleUpdate() async {
    try {
      final data = await getRequestData();
      await process(data);
    } catch (e) {
      await onFailure(e);
    }
  }
}
