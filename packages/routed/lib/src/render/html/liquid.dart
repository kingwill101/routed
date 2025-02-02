import 'package:liquify/liquify.dart';
import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:routed/src/render/html/template_engine.dart';
import 'package:path/path.dart' as p;

/// The `LiquidRoot` class implements the `Root` interface and is responsible
/// for resolving template file paths and reading their contents.
class LiquidRoot implements Root {
  /// The file system to be used for file operations.
  FileSystem fileSystem;

  /// Constructor for `LiquidRoot`.
  ///
  /// If no `fileSystem` is provided, it defaults to `local.LocalFileSystem()`.
  LiquidRoot({FileSystem? fileSystem})
      : fileSystem = fileSystem ?? local.LocalFileSystem();

  /// Resolves the given relative path to a `Source` object.
  ///
  /// This method normalizes the relative path, checks if the file exists,
  /// reads its content, and returns a `Source` object containing the file's URI
  /// and content.
  ///
  /// Throws an exception if the file does not exist.
  @override
  Source resolve(String relPath) {
    final file = fileSystem.file(p.normalize(relPath));
    if (!file.existsSync()) {
      throw Exception('Template file not found: $relPath');
    }
    final content = file.readAsStringSync();
    return Source(file.uri, content, this);
  }
}

/// The `LiquidTemplateEngine` class implements the `TemplateEngine` interface
/// and is responsible for rendering templates using the Liquid templating engine.
class LiquidTemplateEngine implements TemplateEngine {
  /// The file system to be used for file operations.
  final FileSystem _fileSystem;

  /// The root object for resolving template paths.
  Root? _root;

  /// Constructor for `LiquidTemplateEngine`.
  ///
  /// If no `fileSystem` is provided, it defaults to `local.LocalFileSystem()`.
  LiquidTemplateEngine({
    FileSystem? fileSystem,
  }) : _fileSystem = fileSystem ?? const local.LocalFileSystem() {
    _root = LiquidRoot(fileSystem: _fileSystem);
  }

  /// Renders the template with the given name and data.
  ///
  /// This method loads the template from the file system, renders it with the
  /// provided data, and returns the rendered string.
  ///
  /// If an error occurs during rendering, it prints the error and returns an
  /// empty string.
  @override
  Future<String> render(String templateName, Map<String, dynamic> data) async {
    final template = Template.fromFile(templateName, _root!, data: data);

    try {
      return template.render();
    } catch (e) {
      print(e);
      return "";
    }
  }

  /// Loads templates from the specified directory path.
  ///
  /// This method sets the current directory of the file system to the specified
  /// path. If the directory does not exist, it throws an exception.
  @override
  void loadTemplates(String path) {
    final directory = _fileSystem.directory(path);
    if (!directory.existsSync()) {
      throw Exception('Directory not found: $path');
    }
    _fileSystem.currentDirectory = directory.path;
  }
}
