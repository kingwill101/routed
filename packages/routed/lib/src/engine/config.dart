import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:routed/session.dart';
import 'package:routed/src/runtime/shutdown.dart';
import 'package:routed/src/utils/debug.dart';
import 'package:routed/src/view/view_engine.dart';

/// Default ETag generation strategies supported by the engine.
enum EtagStrategy { disabled, strong, weak }

/// Configuration for handling multipart file uploads.
///
/// This class controls limits and behavior for file uploads through multipart
/// form data. It helps protect against denial-of-service attacks and ensures
/// uploaded files meet security requirements.
///
/// Example:
/// ```dart
/// final config = MultipartConfig(
///   maxMemory: 64 * 1024 * 1024,
///   maxFileSize: 20 * 1024 * 1024,
///   allowedExtensions: {'jpg', 'png', 'pdf', 'docx'},
///   uploadDirectory: 'storage/uploads',
/// );
/// ```
class MultipartConfig {
  /// Maximum memory size allowed for file uploads in bytes.
  ///
  /// This limits how much memory can be used for buffering uploads before
  /// they are written to disk. Default is 32MB.
  int maxMemory;

  /// Maximum file size allowed for individual uploads in bytes.
  ///
  /// Any file exceeding this size will be rejected. Default is 10MB.
  int maxFileSize;

  /// Maximum total disk usage per request in bytes.
  ///
  /// This limits the total size of all files in a single request.
  /// Default mirrors [maxMemory].
  int maxDiskUsage;

  /// Set of allowed file extensions for uploads.
  ///
  /// Only files with these extensions will be accepted. Extensions should be
  /// lowercase without the leading dot. Default includes 'jpg', 'jpeg', 'png', 'gif', 'pdf'.
  Set<String> allowedExtensions;

  /// Directory where uploaded files will be stored.
  ///
  /// This path is relative to the application root. Default is 'uploads'.
  final String uploadDirectory;

  /// File permissions for uploaded files in octal notation.
  ///
  /// Default is 0750 (owner: read/write/execute, group: read/execute, others: none).
  final int filePermissions;

  /// Creates a multipart configuration with the given settings.
  ///
  /// All parameters are optional and have sensible defaults for typical applications.
  MultipartConfig({
    this.maxMemory = 32 * 1024 * 1024, // 32MB default
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    int? maxDiskUsage,
    this.allowedExtensions = const {'jpg', 'jpeg', 'png', 'gif', 'pdf'},
    this.uploadDirectory = 'uploads',
    this.filePermissions = 0750,
  }) : maxDiskUsage = maxDiskUsage ?? maxMemory;
}

/// Configuration for HTTP/2 protocol support.
///
/// HTTP/2 provides performance improvements through multiplexing, server push,
/// and header compression. This class configures HTTP/2 behavior for the engine.
///
/// Example:
/// ```dart
/// final config = Http2Config(
///   enabled: true,
///   maxConcurrentStreams: 100,
///   idleTimeout: Duration(minutes: 5),
/// );
/// ```
class Http2Config {
  /// Whether HTTP/2 is enabled.
  ///
  /// When disabled, the engine will only accept HTTP/1.1 connections.
  final bool enabled;

  /// Whether to allow HTTP/2 over cleartext (h2c).
  ///
  /// This enables HTTP/2 without TLS encryption. Should only be used for
  /// development or when TLS is handled by a proxy.
  final bool allowCleartext;

  /// Maximum number of concurrent streams per connection.
  ///
  /// Limits how many requests can be multiplexed on a single connection.
  /// If `null`, uses the default limit.
  final int? maxConcurrentStreams;

  /// Maximum time a connection can remain idle before being closed.
  ///
  /// Connections with no active streams for this duration will be terminated.
  /// If `null`, connections can remain idle indefinitely.
  final Duration? idleTimeout;

  /// Creates an HTTP/2 configuration with the given settings.
  const Http2Config({
    this.enabled = false,
    this.allowCleartext = false,
    this.maxConcurrentStreams,
    this.idleTimeout,
  });

  /// Creates a copy of this configuration with updated values.
  ///
  /// Any parameters not provided will retain their current values.
  Http2Config copyWith({
    bool? enabled,
    bool? allowCleartext,
    int? maxConcurrentStreams,
    Duration? idleTimeout,
  }) {
    return Http2Config(
      enabled: enabled ?? this.enabled,
      allowCleartext: allowCleartext ?? this.allowCleartext,
      maxConcurrentStreams: maxConcurrentStreams ?? this.maxConcurrentStreams,
      idleTimeout: idleTimeout ?? this.idleTimeout,
    );
  }
}

/// Configuration for security features.
///
/// This class groups security-related settings that protect the application
/// from common attacks and vulnerabilities.
class SecurityConfig {
  /// Maximum request size in bytes.
  ///
  /// Requests larger than this will be rejected to prevent memory exhaustion
  /// attacks. Default is 5MB.
  final int maxRequestSize;

  /// List of trusted proxy IP addresses or CIDR ranges.
  ///
  /// When the application runs behind proxies, this list defines which proxies
  /// are trusted to provide the real client IP address.
  final List<String> trustedProxies;

  /// Creates a security configuration with the given settings.
  const SecurityConfig({
    this.maxRequestSize = 5 * 1024 * 1024, // 5MB default
    this.trustedProxies = const [],
  });
}

/// Configuration for feature flags.
///
/// Feature flags allow enabling or disabling specific engine capabilities.
/// This provides fine-grained control over the engine's behavior.
class FeaturesConfig {
  /// Whether to enable security features.
  ///
  /// When enabled, applies security headers, CSRF protection, and other
  /// security measures.
  final bool enableSecurityFeatures;

  /// Whether to enable proxy support.
  ///
  /// When enabled, the engine will process proxy headers like `X-Forwarded-For`
  /// to determine the real client IP address.
  final bool enableProxySupport;

  /// Whether to redirect trailing slashes.
  ///
  /// When enabled, `/path` redirects to `/path/` (or vice versa) if only one
  /// version of the route is defined.
  final bool redirectTrailingSlash;

  /// Whether to handle method not allowed responses.
  ///
  /// When enabled, returns 405 Method Not Allowed (with an `Allow` header)
  /// instead of 404 Not Found when the path matches but the method doesn't.
  final bool handleMethodNotAllowed;

  /// Creates a features configuration with the given flags.
  const FeaturesConfig({
    this.enableSecurityFeatures = true,
    this.enableProxySupport = false,
    this.redirectTrailingSlash = true,
    this.handleMethodNotAllowed = true,
  });
}

/// Configuration for view engine settings.
///
/// This class controls how templates are loaded and rendered by the view engine.
class ViewConfig {
  /// The base directory for view templates.
  ///
  /// This path is relative to the application root. Default is 'views'.
  final String viewPath;

  /// Whether to cache compiled templates.
  ///
  /// When enabled, templates are compiled once and reused, improving performance
  /// in production. Disable for development to see changes immediately.
  final bool cache;

  /// Creates a view configuration with the given settings.
  const ViewConfig({this.viewPath = 'views', this.cache = true});
}

/// Configuration for engine-level feature flags.
///
/// These flags control core engine behaviors related to platform integration,
/// proxies, and security.
class EngineFeatures {
  /// Whether to trust platform-provided headers for client IP.
  ///
  /// When enabled, the engine trusts headers from known platforms like
  /// Cloudflare, Google App Engine, or Fly.io to determine the client IP.
  final bool enableTrustedPlatform;

  /// Whether to enable proxy support.
  ///
  /// When enabled, the engine processes proxy headers to determine the real
  /// client IP address.
  final bool enableProxySupport;

  /// Whether to enable security features.
  ///
  /// When enabled, applies security headers, request validation, and other
  /// security measures.
  final bool enableSecurityFeatures;

  /// Creates an engine features configuration with the given flags.
  const EngineFeatures({
    this.enableTrustedPlatform = false,
    this.enableProxySupport = false,
    this.enableSecurityFeatures = true,
  });
}

/// Configuration for engine security features.
///
/// This class provides fine-grained control over security headers, CSRF
/// protection, CORS, and request size limits.
class EngineSecurityFeatures {
  /// Whether CSRF protection is enabled.
  ///
  /// When enabled, state-changing requests (POST, PUT, DELETE) must include
  /// a valid CSRF token.
  final bool csrfProtection;

  /// Name of the cookie used to store the CSRF token.
  ///
  /// Default is 'csrf_token'.
  final String csrfCookieName;

  /// Content Security Policy header value.
  ///
  /// When set, adds a `Content-Security-Policy` header to responses to
  /// mitigate XSS attacks. If `null`, no CSP header is added.
  final String? csp;

  /// Whether to add the `X-Content-Type-Options: nosniff` header.
  ///
  /// This prevents browsers from MIME-sniffing responses, which can prevent
  /// certain types of attacks.
  final bool xContentTypeOptionsNoSniff;

  /// Maximum age in seconds for HTTP Strict Transport Security (HSTS).
  ///
  /// When set, adds an `Strict-Transport-Security` header to force HTTPS.
  /// If `null`, no HSTS header is added.
  final int? hstsMaxAge;

  /// Value for the `X-Frame-Options` header.
  ///
  /// Controls whether the page can be embedded in frames. Common values are
  /// 'DENY', 'SAMEORIGIN', or 'ALLOW-FROM uri'. If `null`, no header is added.
  final String? xFrameOptions;

  /// Maximum request size in bytes.
  ///
  /// Requests larger than this will be rejected. Default is 10MB.
  final int maxRequestSize;

  /// CORS configuration.
  ///
  /// Controls cross-origin resource sharing policies.
  final CorsConfig cors;

  /// Creates an engine security features configuration.
  const EngineSecurityFeatures({
    this.csrfProtection = true,
    this.csrfCookieName = 'csrf_token',
    this.csp,
    this.xContentTypeOptionsNoSniff = false,
    this.hstsMaxAge,
    this.xFrameOptions,
    this.maxRequestSize = 1024 * 1024 * 10, // 10MB Default
    this.cors = const CorsConfig(),
  });

  /// Creates a copy of this configuration with updated values.
  ///
  /// Any parameters not provided will retain their current values.
  EngineSecurityFeatures copyWith({
    bool? csrfProtection,
    String? csrfCookieName,
    String? csp,
    bool? xContentTypeOptionsNoSniff,
    int? hstsMaxAge,
    String? xFrameOptions,
    int? maxRequestSize,
    CorsConfig? cors,
  }) {
    return EngineSecurityFeatures(
      csrfProtection: csrfProtection ?? this.csrfProtection,
      csrfCookieName: csrfCookieName ?? this.csrfCookieName,
      csp: csp ?? this.csp,
      xContentTypeOptionsNoSniff:
          xContentTypeOptionsNoSniff ?? this.xContentTypeOptionsNoSniff,
      hstsMaxAge: hstsMaxAge ?? this.hstsMaxAge,
      xFrameOptions: xFrameOptions ?? this.xFrameOptions,
      maxRequestSize: maxRequestSize ?? this.maxRequestSize,
      cors: cors ?? this.cors,
    );
  }
}

/// Configuration for Cross-Origin Resource Sharing (CORS).
///
/// CORS controls which domains can make cross-origin requests to the API.
/// This is essential for web applications that access the API from different domains.
///
/// Example:
/// ```dart
/// final config = CorsConfig(
///   enabled: true,
///   allowedOrigins: ['https://example.com', 'https://app.example.com'],
///   allowedMethods: ['GET', 'POST', 'PUT'],
///   allowCredentials: true,
/// );
/// ```
class CorsConfig {
  /// Whether CORS is enabled.
  final bool enabled;

  /// List of allowed origin domains.
  ///
  /// Use '*' to allow all origins (not recommended for production).
  /// Specific origins should include the full protocol and domain,
  /// e.g., 'https://example.com'.
  final List<String> allowedOrigins;

  /// List of allowed HTTP methods for cross-origin requests.
  ///
  /// Default includes GET, POST, PUT, DELETE, PATCH, and OPTIONS.
  final List<String> allowedMethods;

  /// List of allowed request headers.
  ///
  /// Headers that the client is allowed to send. Empty list allows all headers.
  final List<String> allowedHeaders;

  /// Whether credentials (cookies, authorization headers) are allowed.
  ///
  /// When enabled, the `Access-Control-Allow-Credentials` header is set to true.
  final bool allowCredentials;

  /// Maximum time in seconds that preflight responses can be cached.
  ///
  /// This sets the `Access-Control-Max-Age` header. If `null`, no max-age
  /// header is sent.
  final int? maxAge;

  /// List of headers that browsers are allowed to access.
  ///
  /// This sets the `Access-Control-Expose-Headers` header. Headers not in
  /// this list won't be accessible to JavaScript in the browser.
  final List<String> exposedHeaders;

  /// Creates a CORS configuration with the given settings.
  const CorsConfig({
    this.enabled = false,
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'OPTIONS',
    ],
    this.allowedHeaders = const [],
    this.allowCredentials = false,
    this.maxAge,
    this.exposedHeaders = const [],
  });
}

/// Primary configuration for the routing engine.
///
/// This class consolidates all engine settings including features, security,
/// routing behavior, TLS, and view configuration. It provides the main
/// configuration interface for customizing engine behavior.
///
/// Example:
/// ```dart
/// final config = EngineConfig(
///   security: EngineSecurityFeatures(
///     maxRequestSize: 10 * 1024 * 1024,
///     cors: CorsConfig(enabled: true),
///   ),
///   redirectTrailingSlash: true,
///   handleMethodNotAllowed: true,
/// );
/// ```
class EngineConfig {
  final EngineFeatures features;
  final EngineSecurityFeatures security;
  final ViewConfig views;
  final ShutdownConfig shutdown;
  final Http2Config http2;
  final String? tlsCertificatePath;
  final String? tlsKeyPath;
  final String? tlsCertificatePassword;
  final bool? tlsRequestClientCertificate;
  final bool? tlsShared;
  final bool? tlsV6Only;

  // Routing behavior
  final bool redirectTrailingSlash;
  final bool redirectFixedPath;
  final bool handleMethodNotAllowed;
  final bool removeExtraSlash;
  final bool useRawPath;
  final bool unescapePathValues;

  // IP and forwarding
  final bool forwardedByClientIP;
  final List<String> remoteIPHeaders;
  List<String> _trustedProxies = [];
  String? _trustedPlatform;
  List<({InternetAddress address, int prefixLength})> _parsedProxies = [];

  final String templateDirectory;
  final ViewEngine? templateEngine;
  final FileSystem fileSystem;
  final MultipartConfig multipart;
  final String? appKey;
  final bool defaultOptionsEnabled;
  final EtagStrategy etagStrategy;

  /// Cloudflare's client IP header name.
  static const platformCloudflare = 'CF-Connecting-IP';

  /// Google App Engine's client IP header name.
  static const platformGoogleAppEngine = 'X-Appengine-Remote-Addr';

  /// Fly.io's client IP header name.
  static const platformFlyIO = 'Fly-Client-IP';

  /// Creates an engine configuration with the given settings.
  ///
  /// All parameters are optional and have sensible defaults. Common settings
  /// to customize include [security], [redirectTrailingSlash], [trustedProxies],
  /// and [templateEngine].
  EngineConfig({
    EngineFeatures? features,
    EngineSecurityFeatures? security,
    ViewConfig? views,
    bool? redirectTrailingSlash,
    bool? redirectFixedPath,
    bool? handleMethodNotAllowed,
    bool? removeExtraSlash,
    bool? useRawPath,
    bool? unescapePathValues,
    bool? forwardedByClientIP,
    List<String>? remoteIPHeaders,
    List<String>? trustedProxies,
    String? trustedPlatform,
    String? templateDirectory,
    bool? defaultOptionsEnabled,
    EtagStrategy? etagStrategy,
    this.templateEngine,
    this.appKey,
    FileSystem? fileSystem,
    MultipartConfig? multipart,
    ShutdownConfig? shutdown,
    Http2Config? http2,
    this.tlsCertificatePath,
    this.tlsKeyPath,
    this.tlsCertificatePassword,
    this.tlsRequestClientCertificate,
    this.tlsShared,
    this.tlsV6Only,
  }) : features = features ?? const EngineFeatures(),
       security = security ?? const EngineSecurityFeatures(),
       views = views ?? const ViewConfig(),
       shutdown =
           shutdown ??
           const ShutdownConfig(
             enabled: false,
             gracePeriod: Duration(seconds: 20),
             forceAfter: Duration(minutes: 1),
             exitCode: 0,
             notifyReadiness: true,
             signals: {ProcessSignal.sigint, ProcessSignal.sigterm},
           ),
       redirectTrailingSlash = redirectTrailingSlash ?? true,
       redirectFixedPath = redirectFixedPath ?? false,
       handleMethodNotAllowed = handleMethodNotAllowed ?? true,
       removeExtraSlash = removeExtraSlash ?? false,
       useRawPath = useRawPath ?? false,
       unescapePathValues = unescapePathValues ?? true,
       forwardedByClientIP = forwardedByClientIP ?? true,
       remoteIPHeaders =
           remoteIPHeaders ?? const ['X-Forwarded-For', 'X-Real-IP'],
       templateDirectory = templateDirectory ?? 'templates',
       fileSystem = fileSystem ?? const local.LocalFileSystem(),
       multipart = multipart ?? MultipartConfig(),
       defaultOptionsEnabled = defaultOptionsEnabled ?? true,
       etagStrategy = etagStrategy ?? EtagStrategy.disabled,
       http2 = http2 ?? const Http2Config() {
    final engineFeatures = features ?? const EngineFeatures();
    if (engineFeatures.enableProxySupport) {
      _trustedProxies = trustedProxies ?? ['0.0.0.0/0', '::/0'];
    }

    if (engineFeatures.enableTrustedPlatform) {
      _trustedPlatform = trustedPlatform;
    }

    if (engineFeatures.enableProxySupport &&
        _trustedProxies.contains('0.0.0.0/0')) {
      debugPrintWarning(
        'Running with trustedProxies set to trust all IPs (0.0.0.0/0).\n'
        'This is potentially insecure. Consider restricting trusted proxy IPs in production.',
      );
    }
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
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    if (_parsedProxies.isNotEmpty || _trustedProxies.isEmpty) {
      return;
    }
    _parsedProxies = await Future.wait(
      trustedProxies.map((proxy) async {
        final parts = proxy.split('/');
        final host = parts[0];
        final parsed = InternetAddress.tryParse(host);
        final lookupResult = parsed != null
            ? <InternetAddress>[parsed]
            : await InternetAddress.lookup(host);
        final addr = lookupResult.first;
        final prefix = parts.length > 1
            ? int.parse(parts[1])
            : (addr.type == InternetAddressType.IPv4 ? 32 : 128);
        return (address: addr, prefixLength: prefix);
      }),
    );
  }

  Future<void> ensureTrustedProxiesParsed() async {
    if (!features.enableProxySupport || _parsedProxies.isNotEmpty) {
      return;
    }
    await parseTrustedProxies();
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
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
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

  List<String> get trustedProxies {
    return _trustedProxies;
  }

  set trustedProxies(List<String> value) {
    if (!features.enableProxySupport) {
      throw StateError(
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    _trustedProxies = value;
    _parsedProxies = [];
  }

  String? get trustedPlatform => _trustedPlatform;

  set trustedPlatform(String? value) {
    if (!features.enableTrustedPlatform) {
      throw StateError(
        'Trusted platform not enabled. Enable with EngineFeatures.enableTrustedPlatform',
      );
    }
    _trustedPlatform = value;
  }

  /// Creates a copy of this config with the specified fields replaced with new values.
  EngineConfig copyWith({
    EngineFeatures? features,
    EngineSecurityFeatures? security,
    ViewConfig? views,
    bool? redirectTrailingSlash,
    bool? redirectFixedPath,
    bool? handleMethodNotAllowed,
    bool? removeExtraSlash,
    bool? useRawPath,
    bool? unescapePathValues,
    bool? forwardedByClientIP,
    List<String>? remoteIPHeaders,
    List<String>? trustedProxies,
    String? trustedPlatform,
    String? templateDirectory,
    ViewEngine? templateEngine,
    String? appKey,
    bool? defaultOptionsEnabled,
    EtagStrategy? etagStrategy,
    FileSystem? fileSystem,
    MultipartConfig? multipart,
    ShutdownConfig? shutdown,
    Http2Config? http2,
    String? tlsCertificatePath,
    String? tlsKeyPath,
    String? tlsCertificatePassword,
    bool? tlsRequestClientCertificate,
    bool? tlsShared,
    bool? tlsV6Only,
  }) {
    final engineFeatures = features ?? this.features;
    final newConfig = EngineConfig(
      features: engineFeatures,
      security: security ?? this.security,
      views: views ?? this.views,
      redirectTrailingSlash:
          redirectTrailingSlash ?? this.redirectTrailingSlash,
      redirectFixedPath: redirectFixedPath ?? this.redirectFixedPath,
      handleMethodNotAllowed:
          handleMethodNotAllowed ?? this.handleMethodNotAllowed,
      removeExtraSlash: removeExtraSlash ?? this.removeExtraSlash,
      useRawPath: useRawPath ?? this.useRawPath,
      unescapePathValues: unescapePathValues ?? this.unescapePathValues,
      forwardedByClientIP: forwardedByClientIP ?? this.forwardedByClientIP,
      remoteIPHeaders: remoteIPHeaders ?? this.remoteIPHeaders,
      trustedProxies: trustedProxies ?? this.trustedProxies,
      trustedPlatform: trustedPlatform ?? this.trustedPlatform,
      templateDirectory: templateDirectory ?? this.templateDirectory,
      templateEngine: templateEngine ?? this.templateEngine,
      appKey: appKey ?? this.appKey,
      defaultOptionsEnabled:
          defaultOptionsEnabled ?? this.defaultOptionsEnabled,
      etagStrategy: etagStrategy ?? this.etagStrategy,
      fileSystem: fileSystem ?? this.fileSystem,
      multipart: multipart ?? this.multipart,
      shutdown: shutdown ?? this.shutdown,
      http2: http2 ?? this.http2,
      tlsCertificatePath: tlsCertificatePath ?? this.tlsCertificatePath,
      tlsKeyPath: tlsKeyPath ?? this.tlsKeyPath,
      tlsCertificatePassword:
          tlsCertificatePassword ?? this.tlsCertificatePassword,
      tlsRequestClientCertificate:
          tlsRequestClientCertificate ?? this.tlsRequestClientCertificate,
      tlsShared: tlsShared ?? this.tlsShared,
      tlsV6Only: tlsV6Only ?? this.tlsV6Only,
    );

    // Copy over the parsed proxies if they exist
    if (_parsedProxies.isNotEmpty) {
      newConfig._parsedProxies = List.from(_parsedProxies);
    }

    return newConfig;
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

  /// Base cookie options applied when constructing sessions.
  final Options defaultOptions;

  /// Whether the cookie should expire when the browser closes.
  final bool expireOnClose;

  /// SameSite configuration derived from options.
  final SameSite? sameSite;

  /// Partitioned cookie flag.
  final bool? partitioned;

  /// Codecs used when encoding/decoding cookies.
  final List<SecureCookie> codecs;

  /// Lottery configuration surfaced for tooling/tests.
  final List<int>? lottery;

  /// Creates a [SessionConfig].
  ///
  /// The [cookieName] parameter specifies the name of the session cookie.
  /// The [store] parameter specifies the session store implementation.
  /// The [maxAge] parameter specifies the maximum age of the session.
  /// The [path] parameter specifies the path for which the cookie is valid.
  /// The [secure] parameter specifies whether the cookie should only be sent over HTTPS.
  /// The [httpOnly] parameter specifies whether the cookie should be marked as HttpOnly, preventing client-side JavaScript access.
  SessionConfig({
    this.cookieName = 'routed_session',
    required this.store,
    this.maxAge = const Duration(hours: 1),
    this.path = '/',
    this.secure = false,
    this.httpOnly = true,
    Options? defaultOptions,
    this.expireOnClose = false,
    this.sameSite,
    this.partitioned,
    List<SecureCookie>? codecs,
    this.lottery,
  }) : defaultOptions =
           defaultOptions ??
           Options(
             path: path,
             maxAge: expireOnClose ? null : maxAge.inSeconds,
             secure: secure,
             httpOnly: httpOnly,
             sameSite: sameSite,
             partitioned: partitioned,
           ),
       codecs = codecs ?? const [];

  /// Creates a [SessionConfig] that uses cookie storage.
  ///
  /// The [appKey] parameter is required and is used to encrypt and sign the session data.
  /// The [cookieName] parameter specifies the name of the session cookie. Defaults to 'routed_session'.
  /// The [maxAge] parameter specifies the maximum age of the session. Defaults to 1 hour.
  factory SessionConfig.cookie({
    String? appKey,
    List<SecureCookie>? codecs,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
    bool expireOnClose = false,
    Options? options,
  }) {
    final resolvedCodecs = (codecs != null && codecs.isNotEmpty)
        ? codecs
        : [SecureCookie(key: appKey, useEncryption: true, useSigning: true)];
    final resolvedOptions =
        options ??
        Options(
          path: '/',
          maxAge: expireOnClose ? null : maxAge.inSeconds,
          secure: true,
          httpOnly: true,
          sameSite: SameSite.lax,
        );
    return SessionConfig(
      cookieName: cookieName,
      store: CookieStore(
        codecs: resolvedCodecs,
        defaultOptions: resolvedOptions,
      ),
      maxAge: maxAge,
      path: resolvedOptions.path ?? '/',
      secure: resolvedOptions.secure ?? true,
      httpOnly: resolvedOptions.httpOnly ?? true,
      defaultOptions: resolvedOptions,
      expireOnClose: expireOnClose,
      sameSite: resolvedOptions.sameSite,
      partitioned: resolvedOptions.partitioned,
      codecs: resolvedCodecs,
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
    List<SecureCookie>? codecs,
    required String storagePath,
    String cookieName = 'routed_session',
    Duration maxAge = const Duration(hours: 1),
    bool expireOnClose = false,
    Options? options,
    List<int>? lottery,
    FileSystem? fileSystem,
  }) {
    final resolvedCodecs = (codecs != null && codecs.isNotEmpty)
        ? codecs
        : [SecureCookie(key: appKey, useEncryption: true, useSigning: true)];
    final resolvedOptions =
        options ??
        Options(
          path: '/',
          maxAge: expireOnClose ? null : maxAge.inSeconds,
          secure: true,
          httpOnly: true,
        );
    return SessionConfig(
      cookieName: cookieName,
      store: FilesystemStore(
        storageDir: storagePath,
        codecs: resolvedCodecs,
        defaultOptions: resolvedOptions,
        fileSystem: fileSystem,
        lottery: lottery,
      ),
      maxAge: maxAge,
      path: resolvedOptions.path ?? '/',
      secure: resolvedOptions.secure ?? true,
      httpOnly: resolvedOptions.httpOnly ?? true,
      defaultOptions: resolvedOptions,
      expireOnClose: expireOnClose,
      sameSite: resolvedOptions.sameSite,
      partitioned: resolvedOptions.partitioned,
      codecs: resolvedCodecs,
      lottery: lottery,
    );
  }
}
