import '../mixins/context_mixin.dart';
import 'base.dart';

/// Simple ContextView for JSON APIs with context data
///
/// A clean context view that returns JSON context data by default.
/// Users can extend this for simple API endpoints that need to return structured data.
///
/// Example usage:
/// ```dart
/// class StatsView extends ContextView {
///   @override
///   Future<Map<String, dynamic>> getExtraContext() async {
///     return {
///       'user_count': await UserRepository.count(),
///       'post_count': await PostRepository.count(),
///     };
///   }
/// }
/// ```
abstract class ContextView extends View with ContextMixin {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    await sendJson(contextData);
  }
}
