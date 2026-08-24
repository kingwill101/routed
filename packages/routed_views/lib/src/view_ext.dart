import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'view/engine_manager.dart';
import 'view/view_engine.dart';

/// View helpers for [EngineContext] — moved from `routed` to `routed_views`
/// per refactor.md §16.2.
///
/// The extension resolves a template through the configured
/// [ViewEngineManager] and writes the rendered result as HTML.
extension RoutedViewContext on EngineContext {
  /// Whether this context has the view helpers available.
  bool get hasViewSupport => true;

  /// Renders [templateName] through the configured view engine.
  ///
  /// [data] is made available to the template and the current context is
  /// exposed under [kViewEngineContextKey].
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
          // If file exists at filePath, use it; otherwise try templateName as absolute
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
