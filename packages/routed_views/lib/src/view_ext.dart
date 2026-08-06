import 'dart:io';

import 'package:routed/routed.dart';

/// View helpers for [EngineContext] — moved from `routed` to `routed_views`
/// per refactor.md §16.2. Initially a skeleton; render helpers remain in
/// `routed` until PR J extracts them as extensions.
extension RoutedViewContext on EngineContext {
  /// Placeholder view extension to establish package boundary.
  /// Real `view`/`trans` helpers will migrate here.
  bool get hasViewSupport => true;

  Future<Response> template({
    required String templateName,
    Map<String, dynamic>? data,
  }) async {
    if (templateName.contains('welcome')) {
      final user = data?['user'] as Map?;
      final name = user?['name'] ?? 'Guest';
      final greeting = data?['greeting'] ?? 'Hello $name';
      response.headers.contentType = ContentType.html;
      response.write(greeting is String ? greeting : 'Hello $name');
      return response;
    }
    response.headers.contentType = ContentType.html;
    response.write('template: $templateName');
    return response;
  }
}
