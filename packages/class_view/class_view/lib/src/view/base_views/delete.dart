import '../mixins/context_mixin.dart';
import '../mixins/single_object_mixin.dart';
import '../mixins/success_url_mixin.dart';
import 'base.dart';

/// A generic view for deleting an object for APIs
///
/// Users implement two methods and get full delete functionality.
/// Works with any response format - JSON, HTML, XML, text, etc.
/// Mixins work behind the scenes as internal building blocks.
///
/// ## Usage
///
/// ```dart
/// class PostDeleteView extends DeleteView<Post> {
///   @override
///   Future<Post?> getObject() async {
///     final id = await getParam('id');
///     return await PostRepository.findById(id);
///   }
///
///   @override
///   Future<void> performDelete(Post post) async {
///     await PostRepository.delete(post.id);
///   }
///
///   @override
///   String get successUrl => '/posts';  // Optional redirect
/// }
/// ```
///
/// ## What You Get
///
/// - GET requests return object data and confirmation context
/// - DELETE requests process deletion and handle success/failure
/// - Automatic 404 handling if object not found
/// - Automatic success/failure handling
/// - Confirmation data support
/// - Framework-agnostic API patterns
abstract class DeleteView<T> extends View
    with ContextMixin, SingleObjectMixin<T>, SuccessFailureUrlMixin {
  @override
  List<String> get allowedMethods => ['GET', 'DELETE'];

  /// Get the object to delete - one of two methods users need to implement
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

  /// Delete the object - the other method users need to implement
  ///
  /// This method receives the object and should remove it from your data store.
  /// The object is guaranteed to exist (404 check happens before this).
  ///
  /// [object] - The object to delete
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<void> performDelete(Post post) async {
  ///   await PostRepository.delete(post.id);
  ///   // Or soft delete:
  ///   // await PostRepository.update(post.id, {'deleted_at': DateTime.now()});
  /// }
  /// ```
  Future<void> performDelete(T object);

  /// Process the deletion request with error handling
  Future<void> process() async {
    final object = await getObjectOr404();
    await performDelete(object);
    await onSuccess(object);
  }

  @override
  Future<void> get() async {
    // Return object data and confirmation context for GET requests
    final contextData = await getContextData();
    final uri = await getUri();
    final responseData = {
      ...contextData,
      'confirmation_message': 'Are you sure you want to delete this object?',
      'delete_url': uri.path,
      'method': 'DELETE',
    };
    // Default to JSON response, but users can override for different formats
    await sendJson(responseData);
  }

  @override
  Future<void> delete() async {
    try {
      await process();
    } catch (e) {
      await onFailure(e);
    }
  }
}
