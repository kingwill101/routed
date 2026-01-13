import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:liquify/liquify.dart';
import 'package:routed/src/render/html/template_engine.dart';

export 'package:routed/src/view/engines/liquid_engine.dart';

/// The `LiquidRoot` class implements the `Root` interface and is responsible
/// for resolving template file paths and reading their contents.
class LiquidRoot implements Root {
  /// The file system to be used for file operations.
  final FileSystem fileSystem;

  /// Base directory used when resolving relative templates.
  String baseDirectory;

  /// Constructor for `LiquidRoot`.
  ///
  /// If no `fileSystem` is provided, it defaults to `local.LocalFileSystem()`.
  LiquidRoot({FileSystem? fileSystem, String? baseDirectory})
    : fileSystem = fileSystem ?? const local.LocalFileSystem(),
      baseDirectory = _resolveBase(
        fileSystem ?? const local.LocalFileSystem(),
        baseDirectory,
      );

  /// Resolves the given relative path to a `Source` object.
  ///
  /// This method normalizes the relative path, checks if the file exists,
  /// reads its content, and returns a `Source` object containing the file's URI
  /// and content.
  ///
  /// Throws an exception if the file does not exist.
  @override
  Source resolve(String relPath) {
    final file = fileSystem.file(_resolvePath(relPath));
    if (!file.existsSync()) {
      throw Exception('Template file not found: $relPath');
    }

    final content = file.readAsStringSync();
    return Source(file.uri, content, this);
  }

  @override
  Future<Source> resolveAsync(String relPath) async {
    final file = fileSystem.file(_resolvePath(relPath));
    if (!await file.exists()) {
      throw Exception('Template file not found: $relPath');
    }
    final content = await file.readAsString();
    return Source(file.uri, content, this);
  }

  void setBaseDirectory(String? value) {
    baseDirectory = _resolveBase(fileSystem, value);
  }

  String _resolvePath(String relPath) {
    final pathContext = fileSystem.path;
    final normalized = pathContext.normalize(relPath);
    if (pathContext.isAbsolute(normalized)) {
      return normalized;
    }
    return pathContext.normalize(pathContext.join(baseDirectory, normalized));
  }

  static String _resolveBase(FileSystem fs, String? base) {
    final pathContext = fs.path;
    final current = pathContext.normalize(fs.currentDirectory.path);
    final baseValue = (base == null || base.isEmpty) ? current : base;
    final resolved = pathContext.isAbsolute(baseValue)
        ? baseValue
        : pathContext.join(current, baseValue);
    return pathContext.normalize(resolved);
  }
}

class LiquidTemplateEngine implements TemplateEngine {
  final FileSystem _fileSystem;
  Root? _root;
  final Map<String, Function> _funcMap = {};
  final Map<String, Function> _filterMap = {};

  @override
  Map<String, Function> get funcMap => Map.unmodifiable(_funcMap);

  @override
  Map<String, Function> get filterMap => Map.unmodifiable(_filterMap);

  LiquidTemplateEngine({FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem() {
    _root = LiquidRoot(fileSystem: _fileSystem);
  }

  @override
  void addFunc(String name, Function fn) {}

  @override
  void addFilter(String name, Function filter) {
    _filterMap[name] = filter;

    // Register using FilterRegister with proper FilterFunction signature
    FilterRegistry.register(name, (
      dynamic value,
      List<dynamic> arguments,
      Map<String, dynamic> namedArguments,
    ) {
      return filter(value, arguments);
    });
  }

  @override
  Future<String> render(
    String templateName, [
    Map<String, dynamic> data = const {},
  ]) async {
    final template = Template.fromFile(
      templateName,
      _root!,
      data: {
        ...data,
        // Make functions available in template context
        ..._funcMap,
      },
    );

    try {
      return template.render();
    } catch (e) {
      print(e);
      return "";
    }
  }

  @override
  void loadTemplates(String path) {
    final directory = _fileSystem.directory(path);
    if (!directory.existsSync()) {
      throw Exception('Directory not found: $path');
    }
    _fileSystem.currentDirectory = directory.path;
  }

  @override
  String renderContent(String content, [Map<String, dynamic> data = const {}]) {
    Template.parse(content, data: data, root: _root);
    throw UnimplementedError();
  }
}
