import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';

import 'view/engines/liquid_engine.dart';
import 'view/view_engine.dart';

/// Engine-level configuration helpers for the view feature package.
extension RoutedViewEngine on Engine {
  /// Returns the configured view engine, or a default Liquid engine.
  ViewEngine get viewEngine =>
      (config.templateEngine as ViewEngine?) ?? LiquidViewEngine();

  /// Configures the view engine and its template directory.
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
