import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'view/engine_manager.dart';

/// Local stub for Render to break dependency on `routed` render.
/// Original was in `package:routed_core/src/render/render.dart`.
abstract class Render {
  FutureOr<void> render(Response response);
  void writeContentType(Response response);
}

/// View/render extensions for [EngineContext] — migrated from `routed`
/// `src/context/render.dart` per refactor.md §16.2.
///
/// Generic response helpers (`string`, `json`, `html`, `redirect`) live in
/// `package:routed_core` (see [EngineContextHelpers]); this extension only
/// carries view-specific rendering.
extension RoutedViewRender on EngineContext {
  FutureOr<void> viewRender(int statusCode, Render renderer) {
    renderer.writeContentType(response);
    response.statusCode = statusCode;
    return renderer.render(response);
  }

  Future<Response> view(
    String template, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    // Delegate to ViewEngine if available, otherwise write placeholder
    try {
      final manager = container.get<ViewEngineManager>();
      final content = await manager.render(template, data);
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write(content);
    } catch (_) {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write('<!-- view: $template -->');
    }
    return response;
  }
}
