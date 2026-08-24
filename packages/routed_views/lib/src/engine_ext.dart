import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';

import 'package:routed_views/src/view/engines/liquid_engine.dart';
import 'package:routed_views/src/view/view_engine.dart';

/// Configures view rendering on an [Engine].
///
/// These helpers update the engine's typed core configuration. They do not
/// replace provider registration: request helpers such as `ctx.view` still
/// need a `ViewEngineManager` in the request container, normally supplied by
/// `ViewServiceProvider`.
extension RoutedViewEngine on Engine {
  /// Returns the configured [ViewEngine].
  ///
  /// If the core configuration does not contain a [ViewEngine], this getter
  /// creates a default [LiquidViewEngine] for the call. Reading the getter
  /// does not register that fallback with `ViewEngineManager` or persist it in
  /// the engine configuration; use [useViewEngine] or the typed view provider
  /// when the engine should be configured for request handling.
  ViewEngine get viewEngine =>
      (config.templateEngine as ViewEngine?) ?? LiquidViewEngine();

  /// Configures [engine] and, optionally, its template [directory].
  ///
  /// The values are written to a copied [EngineConfig], so existing engine
  /// references remain valid while future request contexts observe the new
  /// configuration. [fileSystem] selects the file system used by the engine
  /// configuration. A `null` optional value leaves the corresponding existing
  /// setting unchanged.
  ///
  /// This method does not add [engine] to a `ViewEngineManager`. Register it
  /// with the manager when extension-based dispatch through `ctx.view` is
  /// required, or use `ViewServiceProvider` to create and register the
  /// configured provider engine during startup.
  ///
  /// ```dart
  /// final engine = Engine();
  /// engine.useViewEngine(LiquidViewEngine(directory: 'views'));
  /// ```
  void useViewEngine(
    ViewEngine engine, {
    String? directory,
    FileSystem? fileSystem,
  }) {
    updateConfig(
      config.copyWith(
        templateEngine: engine,
        templateDirectory: directory,
        fileSystem: fileSystem,
      ),
    );
  }
}
