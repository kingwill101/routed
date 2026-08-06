import 'dart:async';

import 'package:routed/routed.dart';

/// View/render extensions for [EngineContext] — migrated from `routed`
/// `src/context/render.dart` per refactor.md §16.2.
extension RoutedViewRender on EngineContext {
  FutureOr<Response> viewRender(int statusCode, Render renderer) =>
      render(statusCode, renderer);

  Future<Response> view(
    String template, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    return html(template, data: data, statusCode: statusCode);
  }
}
