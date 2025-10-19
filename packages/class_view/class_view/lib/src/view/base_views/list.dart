import '../mixins/context_mixin.dart';
import '../mixins/multiple_object_mixin.dart';
import 'base.dart';

/// A generic view that displays a list of objects for APIs
///
/// Users implement a single method and get full list functionality.
/// Works with any response format - JSON, HTML, XML, text, etc.
/// Mixins work behind the scenes as internal building blocks.
///
/// ## Usage
///
/// ```dart
/// class PostListView extends ListView<Post> {
///   @override
///   int get paginate => 10;  // Optional pagination
///
///   @override
///   Future<({List<T> items, int total})> getObjects({int page = 1, int pageSize = 10}) async {
///     return await PostRepository.findAll(page: page, pageSize: pageSize);
///   }
/// }
/// ```
///
/// ## What You Get
///
/// - GET requests return object list and context
/// - Automatic pagination if paginate is set
/// - Pagination metadata in response
/// - Context data building with object list
/// - Flexible response formatting
/// - Framework-agnostic API patterns
abstract class ListView<T> extends View
    with ContextMixin, MultipleObjectMixin<T> {
  @override
  List<String> get allowedMethods => ['GET'];

  /// Get the list of objects to display - the only method users need to implement
  ///
  /// This method should fetch objects from your data store with pagination support.
  /// Return a record with the list of items and total count.
  ///
  /// [page] - Current page number (1-indexed)
  /// [pageSize] - Number of items per page
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<({List<Post> items, int total})> getObjects({int page = 1, int pageSize = 10}) async {
  ///   final result = await PostRepository.findAll(
  ///     offset: (page - 1) * pageSize,
  ///     limit: pageSize,
  ///   );
  ///   return (items: result.items, total: result.total);
  /// }
  /// ```
  @override
  Future<({List<T> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  });

  /// Alias for getObjectList - cleaner name for users
  Future<({List<T> items, int total})> getObjects({
    int page = 1,
    int pageSize = 10,
  }) {
    return getObjectList(page: page, pageSize: pageSize);
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    // Default to JSON response, but users can override for different formats
    await sendJson(contextData);
  }
}
