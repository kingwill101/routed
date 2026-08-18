import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'view/engine_manager.dart';

/// View/render extensions for [EngineContext] — migrated from `routed`
/// `src/context/render.dart` per refactor.md §16.2.
///
/// Generic response helpers (`string`, `json`, `html`, `redirect`) live in
/// `package:routed_core` (see [EngineContextHelpers]); this extension only
/// carries view-specific rendering.
extension RoutedViewRender on EngineContext {
  Future<Response> view(
    String template, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    final manager = container.get<ViewEngineManager>();
    final content = await manager.render(template, data);
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.html;
    response.write(content);
    return response;
  }
}
