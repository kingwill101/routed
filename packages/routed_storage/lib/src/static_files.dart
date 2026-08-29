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

  /// Mounts a directory from an asynchronous `storage_fs` backend.
  ///
  /// This supports host-native object stores, including Cloudflare R2, that
  /// cannot implement `package:file`.
  void staticStorage(
    String relativePath,
    Filesystem storage, {
    String rootPath = '',
    bool listDirectory = false,
    String indexFile = 'index.html',
  }) {
    _mountStorageStaticDir(
      defaultRouter,
      relativePath,
      StorageFileHandler(
        storage: storage,
        rootPath: rootPath,
        allowDirectoryListing: listDirectory,
        indexFile: indexFile,
      ),
    );
  }

  /// Mounts private storage objects behind time-limited signed URLs.
  ///
  /// Authorize the caller before creating a URL with [signer]. The mounted
  /// route rejects unsigned, expired, or tampered requests before touching
  /// [storage].
  void signedStorage(
    String relativePath,
    Filesystem storage, {
    required StorageSignedUrlSigner signer,
    String rootPath = '',
    String indexFile = 'index.html',
  }) {
    _mountSignedStorageDir(
      defaultRouter,
      relativePath,
      SignedStorageFileHandler(
        storage: storage,
        signer: signer,
        rootPath: rootPath,
        indexFile: indexFile,
      ),
    );
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

  /// Mounts a directory from an asynchronous `storage_fs` backend.
  void staticStorage(
    String relativePath,
    Filesystem storage, {
    String rootPath = '',
    bool listDirectory = false,
    String indexFile = 'index.html',
  }) {
    _mountStorageStaticDir(
      this,
      relativePath,
      StorageFileHandler(
        storage: storage,
        rootPath: rootPath,
        allowDirectoryListing: listDirectory,
        indexFile: indexFile,
      ),
    );
  }

  /// Mounts private storage objects behind time-limited signed URLs.
  void signedStorage(
    String relativePath,
    Filesystem storage, {
    required StorageSignedUrlSigner signer,
    String rootPath = '',
    String indexFile = 'index.html',
  }) {
    _mountSignedStorageDir(
      this,
      relativePath,
      SignedStorageFileHandler(
        storage: storage,
        signer: signer,
        rootPath: rootPath,
        indexFile: indexFile,
      ),
    );
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

void _mountStorageStaticDir(
  Router router,
  String relativePath,
  StorageFileHandler fileHandler,
) {
  if (relativePath.contains(':') || relativePath.contains('*')) {
    throw Exception(
      'URL parameters cannot be used when serving a static folder',
    );
  }

  var route = relativePath.startsWith('/') ? relativePath : '/$relativePath';
  if (route.length > 1 && route.endsWith('/')) {
    route = route.substring(0, route.length - 1);
  }

  Future<Response> serve(EngineContext context, [String file = '']) async {
    await fileHandler.serveToContext(context, file);
    return context.response;
  }

  router
    ..get(route, serve)
    ..head(route, serve);
  final wildcard = p.posix.join(route, '{*filepath}');
  router
    ..get(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    )
    ..head(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    );
}

void _mountSignedStorageDir(
  Router router,
  String relativePath,
  SignedStorageFileHandler fileHandler,
) {
  if (relativePath.contains(':') || relativePath.contains('*')) {
    throw Exception(
      'URL parameters cannot be used when serving a signed storage folder',
    );
  }

  var route = relativePath.startsWith('/') ? relativePath : '/$relativePath';
  if (route.length > 1 && route.endsWith('/')) {
    route = route.substring(0, route.length - 1);
  }

  Future<Response> serve(EngineContext context, [String file = '']) async {
    await fileHandler.serveToContext(context, file);
    return context.response;
  }

  router
    ..get(route, serve)
    ..head(route, serve);
  final wildcard = p.posix.join(route, '{*filepath}');
  router
    ..get(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    )
    ..head(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    );
}
