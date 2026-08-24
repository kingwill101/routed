import 'package:file/file.dart' as file;
import 'package:path/path.dart' as p;
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/src/engine_static_file_sink.dart';
import 'package:server_storage/server_storage.dart';

/// Engine/Router static-file helpers. Lives in the adapter package so foundation
/// `routed` does not depend on or re-export storage APIs.
extension EngineStaticFiles on Engine {
  /// Mounts one file at [relativePath].
  ///
  /// [filePath] is resolved relative to the directory containing the file.
  void staticFile(String relativePath, String filePath, [file.FileSystem? fs]) {
    staticFileFS(
      relativePath,
      filePath,
      Dir(p.dirname(filePath), fileSystem: fs),
    );
  }

  /// Mounts one file using an explicit parent directory [dir].
  void staticFileFS(String relativePath, String filePath, Dir dir) {
    _mountStaticFile(defaultRouter, relativePath, filePath, dir);
  }

  /// Mounts a directory at [relativePath].
  ///
  /// Directory listings are enabled when [listDirectory] is true.
  void static(
    String relativePath,
    String rootPath, {
    file.FileSystem? fileSystem,
    bool listDirectory = false,
  }) {
    staticFS(
      relativePath,
      Dir(rootPath, fileSystem: fileSystem, listDirectory: listDirectory),
    );
  }

  /// Mounts a directory using an explicit [dir] definition.
  void staticFS(String relativePath, Dir dir) {
    _mountStaticDir(defaultRouter, relativePath, dir);
  }
}

/// Adds static-file mounting helpers to an individual router.
extension RouterStaticFiles on Router {
  /// Mounts one file at [relativePath] on this router.
  void staticFile(String relativePath, String filePath, [file.FileSystem? fs]) {
    staticFileFS(
      relativePath,
      filePath,
      Dir(p.dirname(filePath), fileSystem: fs),
    );
  }

  /// Mounts one file using an explicit parent directory [dir].
  void staticFileFS(String relativePath, String filePath, Dir dir) {
    _mountStaticFile(this, relativePath, filePath, dir);
  }

  /// Mounts a directory at [relativePath] on this router.
  void static(
    String relativePath,
    String rootPath, {
    file.FileSystem? fileSystem,
    bool listDirectory = false,
  }) {
    staticFS(
      relativePath,
      Dir(rootPath, fileSystem: fileSystem, listDirectory: listDirectory),
    );
  }

  /// Mounts a directory using an explicit [dir] definition.
  void staticFS(String relativePath, Dir dir) {
    _mountStaticDir(this, relativePath, dir);
  }
}

void _mountStaticFile(
  Router router,
  String relativePath,
  String filePath,
  Dir dir,
) {
  if (relativePath.contains(':') || relativePath.contains('*')) {
    throw Exception('URL parameters cannot be used when serving a static file');
  }

  final fileHandler = FileHandler.fromDir(dir);
  final fileName = p.basename(filePath);

  Future<Response> handler(EngineContext context) async {
    await fileHandler.serveToContext(context, fileName);
    return context.response;
  }

  router
    ..get(relativePath, handler)
    ..head(relativePath, handler);
}

void _mountStaticDir(Router router, String relativePath, Dir dir) {
  if (relativePath.contains(':') || relativePath.contains('*')) {
    throw Exception(
      'URL parameters cannot be used when serving a static folder',
    );
  }

  final urlPattern = p.posix.join(relativePath, '{*filepath}');
  final fileHandler = FileHandler.fromDir(dir);

  Future<Response> handler(EngineContext context) async {
    final requestPath = context.param('filepath')!;
    await fileHandler.serveToContext(context, requestPath);
    return context.response;
  }

  router
    ..get(urlPattern, handler)
    ..head(urlPattern, handler);
}
