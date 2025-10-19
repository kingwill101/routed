import '../mixins/context_mixin.dart';
import '../mixins/single_object_mixin.dart';
import 'base.dart';

/// A generic view that displays a single object for APIs
///
/// Users implement a single method and get full detail functionality.
/// Works with any response format - JSON, HTML, XML, text, etc.
/// Mixins work behind the scenes as internal building blocks.
///
/// ## Usage
///
/// ```dart
/// class PostDetailView extends DetailView<Post> {
///   @override
///   Future<Post?> getObject() async {
///     final id = await getParam('id');
///     return await PostRepository.findById(id);
///   }
/// }
/// ```
///
/// ## What You Get
///
/// - GET requests return object data and context
/// - Automatic 404 handling if object not found
/// - Context data building with object included
/// - Flexible response formatting
/// - Framework-agnostic API patterns
abstract class DetailView<T> extends View
    with ContextMixin, SingleObjectMixin<T> {
  @override
  List<String> get allowedMethods => ['GET'];

  /// Get the object to display - the only method users need to implement
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

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    // Default to JSON response, but users can override for different formats
    await sendJson(contextData);
  }
}
