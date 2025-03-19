import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:routed/session.dart';
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/render/html/template_engine.dart';
import 'package:routed/src/utils/debug.dart';

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
class EngineFeatures {
  final bool enableTrustedPlatform;
  final bool enableProxySupport;
  final bool enableSecurityFeatures;

  const EngineFeatures({
    this.enableTrustedPlatform = false,
    this.enableProxySupport = false,
    this.enableSecurityFeatures = true,
  });
}

class EngineSecurityFeatures {
  final bool csrfProtection;
  final String csrfCookieName;
  final String? csp;
  final bool xContentTypeOptionsNoSniff;
  final int? hstsMaxAge;
  final String? xFrameOptions;
  final int maxRequestSize;

  final CorsConfig cors;

  const EngineSecurityFeatures({
    this.csrfProtection = true,
    this.csrfCookieName = 'csrf_token',
    this.csp,
    this.xContentTypeOptionsNoSniff = true,
    this.hstsMaxAge,
    this.xFrameOptions,
    this.maxRequestSize = 1024 * 1024 * 10, // 10MB Default
    this.cors = const CorsConfig(),
  });
}

class CorsConfig {
  final bool enabled;
  final List<String> allowedOrigins;
  final List<String> allowedMethods;
  final List<String> allowedHeaders;
  final bool allowCredentials;
  final String? exposedHeaders;

  const CorsConfig({
    this.enabled = false,
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'OPTIONS'
    ],
    this.allowedHeaders = const [],
    this.allowCredentials = false,
    this.exposedHeaders,
  });
}

class EngineConfig {
  final EngineFeatures features;
  final EngineSecurityFeatures security;

  List<String> get trustedProxies {
    if (!features.enableProxySupport) {
      throw StateError(
          'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport');
    }
    return _trustedProxies;
  }

  set trustedProxies(List<String> value) {
    if (!features.enableProxySupport) {
      throw StateError(
          'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport');
    }
    _trustedProxies = value;
  }

  String? get trustedPlatform {
    if (!features.enableTrustedPlatform) {
      throw StateError(
          'Trusted platform not enabled. Enable with EngineFeatures.enableTrustedPlatform');
    }
    return _trustedPlatform;
  }

  set trustedPlatform(String? value) {
    if (!features.enableTrustedPlatform) {
      throw StateError(
          'Trusted platform not enabled. Enable with EngineFeatures.enableTrustedPlatform');
    }
    _trustedPlatform = value;
  }

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
  /// Default includes '0.0.0.0/0' and '::/0'.
  List<String> _trustedProxies = [];

  /// Specifies the trusted platform, if any.
  String? _trustedPlatform;

  /// Parsed list of network addresses from the trusted proxies.
  List<({InternetAddress address, int prefixLength})> _parsedProxies = [];

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

  // Predefined trusted platforms
  static const platformCloudflare = 'CF-Connecting-IP';
  static const platformGoogleAppEngine = 'X-Appengine-Remote-Addr';
  static const platformFlyIO = 'Fly-Client-IP';

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
    EngineFeatures? features,
    EngineSecurityFeatures? security,
    this.redirectTrailingSlash = true,
    this.redirectFixedPath = false,
    this.handleMethodNotAllowed = true,
    this.removeExtraSlash = false,
    this.useRawPath = false,
    this.unescapePathValues = true,
    this.forwardedByClientIP = true,
    this.remoteIPHeaders = const ['X-Forwarded-For', 'X-Real-IP'],
    List<String>? trustedProxies,
    String? trustedPlatform,
    this.templateDirectory = 'templates',
    this.templateEngine,
    this.sessionConfig,
    this.appKey,
    FileSystem? fileSystem,
    MultipartConfig? multipart,
    CacheManager? cacheManager,
  })  : features = features ?? const EngineFeatures(),
        security = security ?? const EngineSecurityFeatures(),
        fileSystem = fileSystem ?? const local.LocalFileSystem(),
        multipart = multipart ?? MultipartConfig(),
        cacheManager = cacheManager ?? CacheManager() {
    if (features?.enableProxySupport == true) {
      _trustedProxies = trustedProxies ?? ['0.0.0.0/0', '::/0'];
    }

    if (features?.enableTrustedPlatform == true) {
      _trustedPlatform = trustedPlatform;
    }

    if (this.features.enableProxySupport &&
        _trustedProxies.contains('0.0.0.0/0') == true) {
      debugPrintWarning(
          'Running with trustedProxies set to trust all IPs (0.0.0.0/0).\n'
          'This is potentially insecure. Consider restricting trusted proxy IPs in production.');
    }
    // Register a default file store
    this
        .cacheManager
        .registerStore('file', {'driver': 'file', 'path': 'cache'});
  }

  /// Parses the `trustedProxies` list into a list of `InternetAddress` and prefix length.
  ///
  /// This method should be called during engine initialization to pre-parse the trusted proxy
  /// configurations for efficient lookup. It uses `InternetAddress.lookup` to resolve the
  /// proxy addresses and supports both IPv4 and IPv6 addresses with optional CIDR notation
  /// for specifying the prefix length.
  ///
  /// The parsed proxies are stored in the `_parsedProxies` field.
  Future<void> parseTrustedProxies() async {
    if (!features.enableProxySupport) {
      throw StateError(
          'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport');
    }
    _parsedProxies = await Future.wait(
      trustedProxies.map((proxy) async {
        final parts = proxy.split('/');
        final addr = await InternetAddress.lookup(parts[0]);
        final prefix = parts.length > 1
            ? int.parse(parts[1])
            : (addr.first.type == InternetAddressType.IPv4 ? 32 : 128);
        return (address: addr.first, prefixLength: prefix);
      }),
    );
  }

  /// Checks if the given `InternetAddress` is a trusted proxy.
  ///
  /// This method iterates through the parsed trusted proxies (`_parsedProxies`) and compares
  /// the provided `InternetAddress` against each trusted proxy, taking into account the
  /// prefix length specified in CIDR notation.
  ///
  /// Returns `true` if the address is a trusted proxy, `false` otherwise.
  bool isTrustedProxy(InternetAddress addr) {
    if (!features.enableProxySupport) {
      throw StateError(
          'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport');
    }
    if (_parsedProxies.isEmpty) return false;
    for (final proxy in _parsedProxies) {
      final addrBytes = addr.rawAddress;
      final proxyBytes = proxy.address.rawAddress;
      final prefixBytes = (proxy.prefixLength / 8).ceil();
      if (addrBytes.length != proxyBytes.length) continue;
      var matches = true;
      for (var i = 0; i < prefixBytes && matches; i++) {
        matches = addrBytes[i] == proxyBytes[i];
      }
      if (matches) return true;
    }
    return false;
  }
}

/// Configuration for session management.
class SessionConfig {
  /// The name of the session cookie. Defaults to 'routed_session'.
  final String cookieName;

  /// The session store implementation.
  final Store store;

  /// The maximum age of the session. Defaults to 1 hour.
  final Duration maxAge;

  /// The path for which the cookie is valid. Defaults to '/'.
  final String path;

  /// Whether the cookie should only be sent over HTTPS. Defaults to `false`.
  final bool secure;

  /// Whether the cookie should be marked as HttpOnly, preventing client-side JavaScript access. Defaults to `true`.
  final bool httpOnly;

  /// Creates a [SessionConfig].
  ///
  /// The [cookieName] parameter specifies the name of the session cookie.
  /// The [store] parameter specifies the session store implementation.
  /// The [maxAge] parameter specifies the maximum age of the session.
  /// The [path] parameter specifies the path for which the cookie is valid.
  /// The [secure] parameter specifies whether the cookie should only be sent over HTTPS.
  /// The [httpOnly] parameter specifies whether the cookie should be marked as HttpOnly, preventing client-side JavaScript access.
  const SessionConfig({
    this.cookieName = 'routed_session',
    required this.store,
    this.maxAge = const Duration(hours: 1),
    this.path = '/',
    this.secure = false,
    this.httpOnly = true,
  });

  /// Creates a [SessionConfig] that uses cookie storage.
  ///
  /// The [appKey] parameter is required and is used to encrypt and sign the session data.
  /// The [cookieName] parameter specifies the name of the session cookie. Defaults to 'routed_session'.
  /// The [maxAge] parameter specifies the maximum age of the session. Defaults to 1 hour.
  factory SessionConfig.cookie({
    String? appKey,
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

  /// Creates a [SessionConfig] that uses file storage.
  ///
  /// The [appKey] parameter is required and is used to encrypt and sign the session data.
  /// The [storagePath] parameter specifies the directory where session files will be stored.
  /// The [cookieName] parameter specifies the name of the session cookie. Defaults to 'routed_session'.
  /// The [maxAge] parameter specifies the maximum age of the session. Defaults to 1 hour.
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
