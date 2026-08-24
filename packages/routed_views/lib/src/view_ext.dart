import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'package:routed_views/src/view/engine_manager.dart';
import 'package:routed_views/src/view/view_engine.dart';

/// Renders file-backed templates from an [EngineContext].
///
/// The helper first uses a [ViewEngineManager] when one is registered in the
/// request container. It falls back to the engine in [EngineConfig] when the
/// manager has no matching extension. The current [EngineContext] is added to
/// the template data under [kViewEngineContextKey], which lets request-aware
/// engines such as Liquid expose helpers that read request state.
extension RoutedViewContext on EngineContext {
  /// Whether this extension is available on the context.
  ///
  /// This value only describes that the package extension is in scope. It does
  /// not prove that a view engine or [ViewEngineManager] has been configured;
  /// [template] still throws a [StateError] when neither is available.
  bool get hasViewSupport => true;

  /// Loads and renders the file named [templateName] as HTML.
  ///
  /// A relative name is resolved below the configured view directory when the
  /// file exists there. An absolute path may be used as a fallback when the
  /// configured directory does not contain the requested file. [data] is
  /// copied before the current context is inserted under
  /// [kViewEngineContextKey], so a caller-provided value for that reserved key
  /// is replaced.
  ///
  /// The response is written only after rendering succeeds and is marked as
  /// `text/html`. A [StateError] is thrown when no engine can be resolved;
  /// file-system, parsing, and engine-specific failures are propagated to the
  /// caller.
  ///
  /// ```dart
  /// app.get('/welcome', (ctx) {
  ///   return ctx.template(
  ///     templateName: 'welcome.liquid',
  ///     data: {'name': 'Routed'},
  ///   );
  /// });
  /// ```
  Future<Response> template({
    required String templateName,
    Map<String, dynamic>? data,
  }) async {
    final container = (this as dynamic).container as Container;
    ViewEngine? engine;
    String? filePath;

    final engineConfig = container.has<EngineConfig>()
        ? container.get<EngineConfig>()
        : null;

    if (container.has<ViewEngineManager>()) {
      final manager = container.get<ViewEngineManager>();
      engine = manager.engineForFile(templateName);
      if (engine != null && engineConfig != null) {
        final viewPath = engineConfig.views.viewPath;
        if (viewPath.isNotEmpty) {
          final fs = engineConfig.fileSystem;
          filePath = fs.path.join(viewPath, templateName);
          // If the file exists at filePath, use it; otherwise try templateName
          // as an absolute path.
          if (!fs.file(filePath).existsSync() &&
              fs.file(templateName).existsSync()) {
            filePath = templateName;
          }
        } else {
          filePath = templateName;
        }
      } else {
        filePath = templateName;
      }
    }

    engine ??= engineConfig?.templateEngine as ViewEngine?;
    filePath ??= templateName;
    if (engineConfig != null &&
        filePath == templateName &&
        engineConfig.views.viewPath.isNotEmpty) {
      final fs = engineConfig.fileSystem;
      final candidate = fs.path.join(engineConfig.views.viewPath, templateName);
      if (fs.file(candidate).existsSync()) {
        filePath = candidate;
      }
    }

    if (engine == null) {
      throw StateError('No view engine registered for $templateName');
    }

    final mergedData = <String, dynamic>{...?data, kViewEngineContextKey: this};

    final rendered = await engine.renderFile(filePath, mergedData);
    response.headers.contentType = ContentType.html;
    response.write(rendered);
    return response;
  }
}
