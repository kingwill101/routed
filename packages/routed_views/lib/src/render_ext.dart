import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/view/engine_manager.dart';

/// View/render extensions for [EngineContext] — migrated from `routed`
/// `src/context/render.dart` per refactor.md §16.2.
///
/// Generic response helpers (`string`, `json`, `html`, `redirect`) live in
/// `package:routed_core` (see [EngineContextHelpers]); this extension only
/// carries view-specific rendering.
extension RoutedViewRender on EngineContext {
  /// Renders [template] and writes it as an HTML response.
  ///
  /// [data] is passed to the selected view engine and [statusCode] is used
  /// for the response.
  Future<Response> view(
    String template, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    final manager = container.get<ViewEngineManager>();
    final content = await manager.render(template, data);
    response.statusCode = statusCode;
    // Set the value through the portable header API. Assigning
    // dart:io's ContentType.html is not supported by every Fetch runtime
    // (notably Cloudflare Workers), while the wire representation is the
    // same on native and portable hosts.
    response.headers.set('Content-Type', 'text/html; charset=utf-8');
    response.write(content);
    return response;
  }
}
