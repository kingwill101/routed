import 'package:file/file.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/view/engines/liquid_engine.dart'
    show LiquidViewEngine;
import 'package:routed/src/view/view_engine.dart';

/// Extension on the Engine class to provide view engine functionalities.
extension ViewEngineExtension on Engine {
  /// Gets the current view engine from the configuration.
  ///
  /// Returns null if no view engine has been configured.
  ViewEngine get viewEngine => config.templateEngine ?? LiquidViewEngine();

  /// Configures a view engine for the application.
  ///
  /// This method allows setting up a [ViewEngine] along with its configuration options:
  /// - [engine]: The view engine implementation to use
  /// - [directory]: Optional directory where view templates are stored
  /// - [fileSystem]: Optional custom file system implementation
  ///
  /// Example:
  /// ```dart
  /// engine.useViewEngine(
  ///   LiquidViewEngine(),
  ///   root: LiquidRoot(),
  /// );
  /// ```
  void useViewEngine(
    ViewEngine engine, {
    String? directory,
    FileSystem? fileSystem,
  }) {
    // Create a new config with the updated engine
    final newConfig = config.copyWith(
      templateEngine: engine,
      templateDirectory: directory,
      fileSystem: fileSystem,
    );
    // Update the config and initialize the engine
    updateConfig(newConfig);
  }
}
