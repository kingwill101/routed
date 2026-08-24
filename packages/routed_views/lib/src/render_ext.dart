import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/view/engine_manager.dart';

/// Renders view content from an [EngineContext].
///
/// The extension uses the request container's [ViewEngineManager], then writes
/// the result with a portable `Content-Type: text/html; charset=utf-8` header.
/// Generic response helpers such as `string`, `json`, `html`, and `redirect`
/// remain in `package:routed_core`.
extension RoutedViewRender on EngineContext {
  /// Renders [template] and writes the result as an HTML response.
  ///
  /// The manager selects an engine from the extension in [template], passes
  /// [data] to that engine, and uses [statusCode] for the response. This
  /// helper renders in-memory content through `ViewEngineManager.render`; use
  /// `RoutedViewContext.template` for a file-backed template.
  ///
  /// The request container must contain a `ViewEngineManager`. If no engine
  /// matches the template extension, or if the engine fails, the exception is
  /// propagated and the response is not written by this helper.
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
