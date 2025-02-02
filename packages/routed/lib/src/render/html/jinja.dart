import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:jinja/jinja.dart';
import 'package:path/path.dart' as p;
import 'package:routed/src/render/html/template_engine.dart';
import 'package:jinja/loaders.dart';

/// Creates a default Jinja environment with templates loaded from the file system.
///
/// This function scans the current directory of the provided [fileSystem] for files
/// with extensions specified in [extensions]. It reads the content of these files
/// and loads them into a Jinja [Environment] using a [MapLoader].
///
/// - [fileSystem]: The file system to scan for template files.
/// - [extensions]: A list of file extensions to consider as templates. Defaults to [".html"].
///
/// Returns an [Environment] with the loaded templates.
Environment defaultEngine(FileSystem fileSystem,
    {List<String> extensions = const [".html"]}) {
  // List all files in the current directory recursively.
  final files = fileSystem.currentDirectory.listSync(recursive: true);

  // Map to store template names and their content.
  Map<String, String> templates = {};

  // Iterate over each file system entity.
  for (var entity in files) {
    // Check if the entity is a file and has one of the specified extensions.
    if (entity is File && extensions.contains(p.extension(entity.path))) {
      // Read the file content and store it in the templates map.
      templates[p.basename(entity.path)] = entity.readAsStringSync();
    }
  }

  // Create and return a Jinja environment with the loaded templates.
  return Environment(
    loader: MapLoader(templates),
  );
}

/// A template engine implementation using Jinja for rendering HTML templates.
class JinjaTemplateEngine implements TemplateEngine {
  /// The Jinja environment used for rendering templates.
  late Environment _environment;

  /// A map to store compiled templates by their names.
  final Map<String, Template> _templates = {};

  /// The file system used to load templates.
  final FileSystem _fileSystem;

  /// Creates an instance of [JinjaTemplateEngine].
  ///
  /// - [fileSystem]: The file system to use for loading templates. Defaults to [local.LocalFileSystem].
  /// - [environment]: An optional Jinja environment. If not provided, a default environment is created.
  JinjaTemplateEngine({
    FileSystem? fileSystem,
    Environment? environment,
  }) : _fileSystem = fileSystem ?? const local.LocalFileSystem() {
    // Initialize the Jinja environment.
    _environment = environment ?? defaultEngine(_fileSystem);
  }

  /// Renders a template with the given [templateName] and [data].
  ///
  /// - [templateName]: The name of the template to render.
  /// - [data]: A map of data to pass to the template.
  ///
  /// Returns the rendered template as a string.
  ///
  /// Throws an [Exception] if the template is not found.
  @override
  Future<String> render(String templateName, Map<String, dynamic> data) async {
    // Retrieve the template from the map.
    final template = _templates[templateName];

    // Throw an exception if the template is not found.
    if (template == null) {
      throw Exception('Template not found: $templateName');
    }

    try {
      // Render the template with the provided data.
      return template.render(data);
    } catch (e, s) {
      // Print the error and stack trace, and return an empty string in case of an error.
      print(e);
      print(s);
      return "";
    }
  }

  /// Loads templates from the specified directory [path].
  ///
  /// This method scans the directory recursively for files with a ".html" extension,
  /// reads their content, and compiles them into Jinja templates.
  ///
  /// - [path]: The path of the directory to load templates from.
  @override
  void loadTemplates(String path) {
    // Get the directory from the file system.
    final directory = _fileSystem.directory(path);

    // Iterate over each file system entity in the directory recursively.
    for (var entity in directory.listSync(recursive: true)) {
      // Check if the entity is a file and has a ".html" extension.
      if (entity is File && entity.path.endsWith('.html')) {
        // Get the relative path of the file from the specified directory.
        final name = p.relative(entity.path, from: path);

        // Read the file content.
        final content = entity.readAsStringSync();

        // Compile the content into a Jinja template and store it in the map.
        _templates[name] = _environment.fromString(content);
      }
    }
  }
}
