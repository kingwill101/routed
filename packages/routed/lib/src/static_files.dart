import 'package:file/file.dart' as file;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:routed/src/file_handler.dart';

mixin StaticFileHandler {
  Router get router {
    if (this is Router) {
      return this as Router;
    } else if (this is Engine) {
      return (this as Engine).defaultRouter;
    } else {
      throw Exception('This class does not have a router');
    }
  }

  void staticFile(String relativePath, String filePath, [file.FileSystem? fs]) {
    staticFileFS(
      relativePath,
      filePath,
      Dir(p.dirname(filePath), fileSystem: fs),
    );
  }

  void staticFileFS(String relativePath, String filePath, Dir fs) {
    if (relativePath.contains(':') || relativePath.contains('*')) {
      throw Exception(
        'URL parameters cannot be used when serving a static file',
      );
    }

    final fileHandler = FileHandler.fromDir(fs);
    final fileName = p.basename(filePath);

    Future<Response> handler(EngineContext context) async {
      await fileHandler.serveFile(context, fileName);
      return context.response;
    }

    router.get(relativePath, handler);
    router.head(relativePath, handler);
  }

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

  void staticFS(String relativePath, Dir dir) {
    if (relativePath.contains(':') || relativePath.contains('*')) {
      throw Exception(
        'URL parameters cannot be used when serving a static folder',
      );
    }

    final urlPattern = p.join(relativePath, '{*filepath}');
    final fileHandler = FileHandler.fromDir(dir);

    Future<Response> handler(EngineContext context) async {
      final requestPath = context.param('filepath') as String;
      await fileHandler.serveFile(context, requestPath);
      return context.response;
    }

    router.get(urlPattern, handler);
    router.head(urlPattern, handler);
  }
}
