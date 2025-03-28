import 'package:routed/routed.dart';
import 'package:routed/src/file_handler.dart';
import 'package:file/file.dart' as file;
import 'package:path/path.dart' as p;

mixin StaticFileHandler {
  Router get router {
    if (this is Router) {
      return this as Router;
    } else if (this is Engine) {
      return (this as Engine).defaultRouter as Router;
    } else {
      throw Exception('This class does not have a router');
    }
  }

  void staticFile(String relativePath, String filePath, [file.FileSystem? fs]) {
    staticFileFS(
        relativePath, filePath, Dir(p.dirname(filePath), fileSystem: fs));
  }

  void staticFileFS(String relativePath, String filePath, Dir fs) {
    if (relativePath.contains(':') || relativePath.contains('*')) {
      throw Exception(
          'URL parameters cannot be used when serving a static file');
    }

    final fileHandler = FileHandler.fromDir(fs);
    final fileName = p.basename(filePath);

    handler(EngineContext context) async {
      await fileHandler.serveFile(context.request.httpRequest, fileName);
    }

    router.get(relativePath, handler);
    router.head(relativePath, handler);
  }

  void static(String relativePath, String rootPath, [file.FileSystem? fs]) {
    staticFS(relativePath, Dir(rootPath, fileSystem: fs));
  }

  void staticFS(String relativePath, Dir dir) {
    if (relativePath.contains(':') || relativePath.contains('*')) {
      throw Exception(
          'URL parameters cannot be used when serving a static folder');
    }

    final urlPattern = p.join(relativePath, '{*filepath}');
    final fileHandler = FileHandler.fromDir(dir);

    handler(EngineContext context) async {
      final requestPath = context.param('filepath') as String;
      await fileHandler.serveFile(context.request.httpRequest, requestPath);
    }

    router.get(urlPattern, handler);
    router.head(urlPattern, handler);
  }
}
