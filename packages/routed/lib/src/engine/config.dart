import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:routed/session.dart';
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/render/html/template_engine.dart';

/// Configuration for handling multipart file uploads.
class MultipartConfig {
  /// Maximum memory size allowed for file uploads in bytes.
  /// Default is 32MB.
  int maxMemory;

  /// Maximum file size allowed for uploads in bytes.
  /// Default is 10MB.
  int maxFileSize;

  /// Set of allowed file extensions for uploads.
  /// Default includes 'jpg', 'jpeg', 'png', 'gif', 'pdf'.
  Set<String> allowedExtensions;

  /// Directory where uploaded files will be stored.
  /// Default is 'uploads'.
  final String uploadDirectory;

  /// File permissions for the uploaded files.
  /// Default is 0750.
  final int filePermissions;

  /// Constructor for [MultipartConfig].
  ///
  /// [maxMemory] sets the maximum memory size for file uploads.
  /// [maxFileSize] sets the maximum file size for uploads.
  /// [allowedExtensions] sets the allowed file extensions for uploads.
  /// [uploadDirectory] sets the directory for storing uploaded files.
  /// [filePermissions] sets the file permissions for uploaded files.
  MultipartConfig({
    this.maxMemory = 32 * 1024 * 1024, // 32MB default
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    this.allowedExtensions = const {'jpg', 'jpeg', 'png', 'gif', 'pdf'},
    this.uploadDirectory = 'uploads',
    this.filePermissions = 0750,
  });
}

/// Configuration for the engine.
class EngineConfig {
  // Routing behavior

  /// Whether to redirect requests with a trailing slash.
  /// Default is true.
  bool redirectTrailingSlash;

  /// Whether to redirect requests with a fixed path.
  /// Default is false.
  bool redirectFixedPath;

  /// Whether to handle method not allowed errors.
  /// Default is true.
  bool handleMethodNotAllowed;

  /// Whether to remove extra slashes in the URL.
  /// Default is false.
  bool removeExtraSlash;

  /// Whether to use the raw path from the URL.
  /// Default is false.
  bool useRawPath;

  /// Whether to unescape path values.
  /// Default is true.
  bool unescapePathValues;

  // IP and forwarding

  /// Whether to trust the client IP from the forwarded headers.
  /// Default is true.
  bool forwardedByClientIP;

  /// List of headers to check for the client IP.
  /// Default includes 'X-Forwarded-For' and 'X-Real-IP'.
  List<String> remoteIPHeaders;

  /// List of trusted proxies.
  /// Default is an empty list.
  List<String> trustedProxies;

  /// Directory for storing templates.
  /// Default is 'templates'.
  String templateDirectory;

  /// Template engine for rendering templates.
  TemplateEngine? templateEngine;

  /// File system to use.
  /// Default is the local file system.
  FileSystem fileSystem;

  /// Configuration for handling multipart file uploads.
  MultipartConfig multipart;

  SessionConfig? sessionConfig;

  final String? appKey;

  /// Cache manager for handling cache stores.
  CacheManager cacheManager;

  /// Constructor for [EngineConfig].
  ///
  /// [redirectTrailingSlash] sets whether to redirect requests with a trailing slash.
  /// [redirectFixedPath] sets whether to redirect requests with a fixed path.
  /// [handleMethodNotAllowed] sets whether to handle method not allowed errors.
  /// [removeExtraSlash] sets whether to remove extra slashes in the URL.
  /// [useRawPath] sets whether to use the raw path from the URL.
  /// [unescapePathValues] sets whether to unescape path values.
  /// [forwardedByClientIP] sets whether to trust the client IP from the forwarded headers.
  /// [remoteIPHeaders] sets the list of headers to check for the client IP.
  /// [trustedProxies] sets the list of trusted proxies.
  /// [templateDirectory] sets the directory for storing templates.
  /// [templateEngine] sets the template engine for rendering templates.
  /// [fileSystem] sets the file system to use.
  /// [multipart] sets the configuration for handling multipart file uploads.
  /// [cacheManager] sets the cache manager for handling cache stores.
  EngineConfig({
    this.redirectTrailingSlash = true,
    this.redirectFixedPath = false,
    this.handleMethodNotAllowed = true,
    this.removeExtraSlash = false,
    this.useRawPath = false,
    this.unescapePathValues = true,
    this.forwardedByClientIP = true,
    this.remoteIPHeaders = const ['X-Forwarded-For', 'X-Real-IP'],
    this.trustedProxies = const [],
    this.templateDirectory = 'templates',
    this.templateEngine,
    this.sessionConfig,
    this.appKey,
    FileSystem? fileSystem,
    MultipartConfig? multipart,
    CacheManager? cacheManager,
  })  : fileSystem = fileSystem ?? const local.LocalFileSystem(),
        multipart = multipart ?? MultipartConfig(),
        cacheManager = cacheManager ?? CacheManager() {
    // Register a default file store
    this
        .cacheManager
        .registerStore('file', {'driver': 'file', 'path': 'cache'});
  }
}

class SessionConfig {
  final String cookieName;
  final Store store;
  final Duration maxAge;
  final String path;
  final bool secure;
  final bool httpOnly;

  const SessionConfig({
    this.cookieName = 'routed_session',
    required this.store,
    this.maxAge = const Duration(hours: 1),
    this.path = '/',
    this.secure = false,
    this.httpOnly = true,
  });

  factory SessionConfig.cookie({
    required String appKey,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
  }) {
    return SessionConfig(
      cookieName: cookieName,
      store: CookieStore(
        codecs: [SecureCookie(key: appKey)],
        defaultOptions: Options(
          path: '/',
          maxAge: maxAge.inSeconds,
          secure: true,
          httpOnly: true,
        ),
      ),
      maxAge: maxAge,
    );
  }

  factory SessionConfig.file({
    required String appKey,
    required String storagePath,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
  }) {
    return SessionConfig(
      cookieName: cookieName,
      store: FilesystemStore(
        storageDir: storagePath,
        codecs: [SecureCookie(key: appKey)],
        defaultOptions: Options(
          maxAge: maxAge.inSeconds,
          secure: true,
          httpOnly: true,
        ),
      ),
      maxAge: maxAge,
    );
  }
}
