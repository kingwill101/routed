import 'package:file/file.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/render/html/jinja.dart';
import 'package:routed/src/render/html/liquid.dart';
import 'package:routed/src/render/html/template_engine.dart';

/// Extension on the Engine class to provide template engine functionalities.
extension TemplateEngineExtension on Engine {
  /// Getter to retrieve the current template engine from the configuration.
  TemplateEngine? get templateEngine => config.templateEngine;

  /// Sets the template engine to be used by the engine.
  ///
  /// This method allows the user to specify a [TemplateEngine] along with
  /// optional parameters for the template directory and file system.
  ///
  /// - [engine]: The template engine to be used.
  /// - [directory]: Optional. The directory where templates are stored.
  /// - [fileSystem]: Optional. The file system to be used for file operations.
  void useTemplateEngine(
    TemplateEngine engine, {
    String? directory,
    FileSystem? fileSystem,
  }) {
    // Set the template engine in the configuration.
    config.templateEngine = engine;

    // If a directory is provided, set it in the configuration.
    if (directory != null) {
      config.templateDirectory = directory;
    }

    // If a file system is provided, set it in the configuration.
    if (fileSystem != null) {
      config.fileSystem = fileSystem;
    }

    // Load templates from the specified directory.
    engine.loadTemplates(config.templateDirectory);
  }

  /// Configures the engine to use the Jinja template engine.
  ///
  /// This method sets up the Jinja template engine with optional parameters
  /// for the template directory and file system.
  ///
  /// - [directory]: Optional. The directory where Jinja templates are stored.
  /// - [fileSystem]: Optional. The file system to be used for file operations.
  void useJinja({
    String? directory,
    FileSystem? fileSystem,
  }) {
    useTemplateEngine(
      JinjaTemplateEngine(
        fileSystem: fileSystem ?? config.fileSystem,
      ),
      directory: directory,
      fileSystem: fileSystem,
    );
  }

  /// Configures the engine to use the Liquid template engine.
  ///
  /// This method sets up the Liquid template engine with optional parameters
  /// for the template directory and file system.
  ///
  /// - [directory]: Optional. The directory where Liquid templates are stored.
  /// - [fileSystem]: Optional. The file system to be used for file operations.
  void useLiquid({
    String? directory,
    FileSystem? fileSystem,
  }) {
    useTemplateEngine(
      LiquidTemplateEngine(
        fileSystem: fileSystem ?? config.fileSystem,
      ),
      directory: directory,
      fileSystem: fileSystem,
    );
  }
}
