import '../mixins/context_mixin.dart';
import '../mixins/template_response_mixin.dart';
import 'base.dart';

/// Generic view combining common functionality
///
/// A comprehensive view that combines context handling and template rendering.
/// This view provides a foundation for complex views that need both context data
/// and template rendering capabilities.
///
/// Example usage:
/// ```dart
/// class DashboardView extends GenericView {
///   @override
///   String get templateName => 'dashboard.html';
///
///   @override
///   Future<Map<String, dynamic>> getExtraContext() async {
///     return {
///       'stats': await getStats(),
///       'notifications': await getNotifications(),
///     };
///   }
/// }
/// ```
abstract class GenericView extends View
    with ContextMixin, TemplateResponseMixin {
  @override
  List<String> get allowedMethods => ['GET'];

  /// Override to customize initialization
  @override
  Future<void> setup() async {
    await super.setup();
    // Custom initialization can be added here by subclasses
  }

  @override
  Future<void> get() async {
    // Default behavior: if templateName is provided, render template
    // Otherwise, return JSON context data
    if (templateName != null) {
      final contextData = await getContextData();
      await renderToResponse(contextData, templateName: templateName);
    } else {
      final contextData = await getContextData();
      await sendJson(contextData);
    }
  }
}
