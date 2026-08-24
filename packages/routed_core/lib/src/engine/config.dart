import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart' as local;
import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/provider/typed_provider.dart';
import 'package:routed_core/src/runtime/shutdown.dart';
import 'package:routed_core/src/security/network.dart';
import 'package:routed_core/src/utils/debug.dart';

/// Default ETag generation strategies supported by the engine.
enum EtagStrategy {
  /// Does not generate or validate entity tags.
  disabled,

  /// Generates a content-sensitive entity tag.
  strong,

  /// Generates a representation-equivalent weak entity tag.
  weak,
}

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
class MultipartConfig implements ValidatableConfiguration {
  /// Creates a multipart configuration with the given settings.
  ///
  /// All parameters are optional and have sensible defaults for typical applications.
  MultipartConfig({
    this.maxMemory = 32 * 1024 * 1024, // 32MB default
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    int? maxDiskUsage,
    Set<String>? allowedExtensions,
    this.uploadDirectory = 'uploads',
    this.filePermissions = 0x1e8,
  }) : maxDiskUsage = maxDiskUsage ?? maxMemory,
       allowedExtensions = Set<String>.unmodifiable(
         (allowedExtensions ?? const {'jpg', 'jpeg', 'png', 'gif', 'pdf'})
             .map((extension) => extension.toLowerCase().trim())
             .where((extension) => extension.isNotEmpty),
       );

  /// Maximum memory size allowed for file uploads in bytes.
  ///
  /// This limits how much memory can be used for buffering uploads before
  /// they are written to disk. Default is 32MB.
  final int maxMemory;

  /// Maximum file size allowed for individual uploads in bytes.
  ///
  /// Any file exceeding this size will be rejected. Default is 10MB.
  final int maxFileSize;

  /// Maximum total disk usage per request in bytes.
  ///
  /// This limits the total size of all files in a single request.
  /// Default mirrors [maxMemory].
  final int maxDiskUsage;

  /// Set of allowed file extensions for uploads.
  ///
  /// Only files with these extensions will be accepted. Extensions should be
  /// lowercase without the leading dot. Default includes 'jpg', 'jpeg', 'png', 'gif', 'pdf'.
  final Set<String> allowedExtensions;

  /// Directory where uploaded files will be stored.
  ///
  /// This path is relative to the application root. Default is 'uploads'.
  final String uploadDirectory;

  /// File permissions for uploaded files in octal notation.
  ///
  /// Default is 0750 (owner: read/write/execute, group: read/execute, others: none).
  final int filePermissions;

  @override
  void validate(ConfigValidationContext context) {
    context.require(maxMemory > 0, 'maxMemory', 'must be greater than zero');
    context.require(
      maxFileSize > 0,
      'maxFileSize',
      'must be greater than zero',
    );
    context.require(
      maxDiskUsage > 0,
      'maxDiskUsage',
      'must be greater than zero',
    );
    context.require(
      uploadDirectory.trim().isNotEmpty,
      'uploadDirectory',
      'cannot be empty',
    );
    context.require(
      filePermissions >= 0 && filePermissions <= 0x1ff,
      'filePermissions',
      'must be a valid Unix permission value',
    );
    for (final extension in allowedExtensions) {
      context.require(
        extension.isNotEmpty && !extension.contains('.'),
        'allowedExtensions',
        'extensions must be non-empty and omit the leading dot',
      );
    }
  }
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
  /// Creates an HTTP/2 configuration with the given settings.
  const Http2Config({
    this.enabled = false,
    this.allowCleartext = false,
    this.maxConcurrentStreams,
    this.idleTimeout,
  });

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
  /// Creates a security configuration with the given settings.
  const SecurityConfig({
    this.maxRequestSize = 5 * 1024 * 1024, // 5MB default
    this.trustedProxies = const [],
  });

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
}

/// Configuration for feature flags.
///
/// Feature flags allow enabling or disabling specific engine capabilities.
/// This provides fine-grained control over the engine's behavior.
class FeaturesConfig {
  /// Creates a features configuration with the given flags.
  const FeaturesConfig({
    this.enableSecurityFeatures = true,
    this.enableProxySupport = false,
    this.redirectTrailingSlash = true,
    this.handleMethodNotAllowed = true,
  });

  /// Whether to enable security features.
  ///
  /// When enabled, applies security headers, CSRF protection, and other
  /// security measures.
  final bool enableSecurityFeatures;

  /// Whether to enable proxy support.
  ///
  /// When enabled, the engine will process proxy headers like `X-Forwarded-For`
  /// to determine the real client IP address. `trustedProxies` must contain
  /// the explicit proxy networks before this feature can boot.
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
}

/// Configuration for view engine settings.
///
/// This class controls how templates are loaded and rendered by the view engine.
class ViewConfig {
  /// Creates a view configuration with the given settings.
  const ViewConfig({this.viewPath = 'views', this.cache = true});

  /// The base directory for view templates.
  ///
  /// This path is relative to the application root. Default is 'views'.
  final String viewPath;

  /// Whether to cache compiled templates.
  ///
  /// When enabled, templates are compiled once and reused, improving performance
  /// in production. Disable for development to see changes immediately.
  final bool cache;
}

/// Configuration for engine-level feature flags.
///
/// These flags control core engine behaviors related to platform integration,
/// proxies, and security.
class EngineFeatures {
  /// Creates an engine features configuration with the given flags.
  const EngineFeatures({
    this.enableTrustedPlatform = false,
    this.enableProxySupport = false,
    this.enableSecurityFeatures = true,
    this.enableRequestZones = true,
    this.enableRequestContainerFastPath = false,
    this.enableTrieRouting = false,
    this.enableSecureRequestIds = false,
  });

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

  /// Whether to wrap each request in its own AppZone.
  ///
  /// Disabling this can improve performance but prevents use of AppZone helpers
  /// and zone-based lookups during request handling.
  final bool enableRequestZones;

  /// Whether to disable request-scoped containers and use a read-only root.
  ///
  /// When enabled, request-scoped bindings are not registered.
  final bool enableRequestContainerFastPath;

  /// Whether to enable the optional segment-trie router.
  ///
  /// When disabled, the engine uses the default matcher.
  final bool enableTrieRouting;

  /// Whether to use cryptographically secure request IDs.
  ///
  /// Defaults to `false` for faster request ID generation.
  final bool enableSecureRequestIds;
}

/// Configuration for engine security features.
///
/// This class provides fine-grained control over security headers, CSRF
/// protection, CORS, and request size limits.
class EngineSecurityFeatures {
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
class EngineConfig implements ValidatableConfiguration {
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
    int? pathInternCacheSize,
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
       pathInternCacheSize = pathInternCacheSize ?? 1000,
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
      // Forwarded client-IP headers are attacker-controlled until the
      // immediate proxy network is explicitly configured. Do not silently
      // trust every IPv4/IPv6 address when proxy support is enabled.
      _trustedProxies = trustedProxies ?? [];
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

  /// Feature flags controlling platform, proxy, and routing behavior.
  final EngineFeatures features;

  /// Security headers, request limits, and CORS settings.
  final EngineSecurityFeatures security;

  /// View-template loading settings.
  final ViewConfig views;

  /// Graceful shutdown settings.
  final ShutdownConfig shutdown;

  /// HTTP/2 protocol settings.
  final Http2Config http2;

  /// Path to the TLS certificate file.
  final String? tlsCertificatePath;

  /// Path to the TLS private key file.
  final String? tlsKeyPath;

  /// Password used to unlock the TLS certificate, when required.
  final String? tlsCertificatePassword;

  /// Whether the TLS server requests a client certificate.
  final bool? tlsRequestClientCertificate;

  /// Whether the TLS server allows shared listening sockets.
  final bool? tlsShared;

  /// Whether the TLS listener is restricted to IPv6-only connections.
  final bool? tlsV6Only;

  // Routing behavior
  /// Whether routes may redirect between trailing-slash forms.
  final bool redirectTrailingSlash;

  /// Whether fixed-path normalization redirects are enabled.
  final bool redirectFixedPath;

  /// Whether matching paths with an unsupported method return `405`.
  final bool handleMethodNotAllowed;

  /// Whether repeated slashes are removed during path normalization.
  final bool removeExtraSlash;

  /// Whether the raw request path is used instead of the decoded path.
  final bool useRawPath;

  /// Whether percent-encoded path parameter values are decoded.
  final bool unescapePathValues;

  /// Maximum number of normalized paths retained in the intern cache.
  final int pathInternCacheSize;

  // IP and forwarding
  /// Whether forwarded headers are used to determine the client address.
  final bool forwardedByClientIP;

  /// Header names checked for forwarded client addresses.
  final List<String> remoteIPHeaders;
  List<String> _trustedProxies = [];
  String? _trustedPlatform;
  List<NetworkMatcher> _parsedProxyNetworks = [];
  bool _trustedProxiesParsed = false;

  /// Directory containing application templates.
  final String templateDirectory;

  /// Optional template engine instance supplied by the application.
  final dynamic templateEngine;

  /// File system used for template and upload access.
  final FileSystem fileSystem;

  /// Multipart upload limits and storage settings.
  final MultipartConfig multipart;

  /// Application key used by providers that need a signing secret.
  final String? appKey;

  /// Whether the engine automatically responds to `OPTIONS` requests.
  final bool defaultOptionsEnabled;

  /// Entity-tag generation strategy.
  final EtagStrategy etagStrategy;

  /// Cloudflare's client IP header name.
  static const platformCloudflare = 'CF-Connecting-IP';

  /// Google App Engine's client IP header name.
  static const platformGoogleAppEngine = 'X-Appengine-Remote-Addr';

  /// Fly.io's client IP header name.
  static const platformFlyIO = 'Fly-Client-IP';

  /// Parses trusted proxy networks without requiring socket APIs for IP/CIDR
  /// values. Hostname proxies retain Dart IO DNS lookup support when available.
  Future<void> parseTrustedProxies() async {
    if (!features.enableProxySupport) {
      throw StateError(
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    if (_trustedProxiesParsed) return;

    final parsedNetworks = <NetworkMatcher>[];
    for (final proxy in trustedProxies) {
      final direct = NetworkMatcher.maybeParse(proxy);
      if (direct != null) {
        parsedNetworks.add(direct);
        continue;
      }

      // Hostname proxies retain Dart IO DNS support. Portable runtimes do not
      // expose DNS sockets, so an unsupported lookup fails closed.
      final parts = proxy.split('/');
      final host = parts.first.trim();
      try {
        final lookupResult = await InternetAddress.lookup(host);
        for (final address in lookupResult) {
          final prefix = parts.length > 1
              ? int.tryParse(parts[1].trim())
              : null;
          final network = NetworkMatcher.maybeParse(
            '${address.address}/${prefix ?? (address.type == InternetAddressType.IPv4 ? 32 : 128)}',
          );
          if (network != null) parsedNetworks.add(network);
        }
      } catch (_) {
        // Keep the proxy untrusted when the host cannot resolve it.
      }
    }
    _parsedProxyNetworks = parsedNetworks;
    _trustedProxiesParsed = true;
  }

  /// Ensures configured trusted proxy networks have been parsed.
  Future<void> ensureTrustedProxiesParsed() async {
    if (!features.enableProxySupport || _trustedProxiesParsed) {
      return;
    }
    await parseTrustedProxies();
  }

  /// Checks if the given `InternetAddress` is a trusted proxy.
  ///
  /// This method compares the provided [InternetAddress] against parsed
  /// trusted proxy networks.
  ///
  /// Returns `true` if the address is a trusted proxy, `false` otherwise.
  bool isTrustedProxy(InternetAddress addr) {
    if (!features.enableProxySupport) {
      throw StateError(
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    return _parsedProxyNetworks.any((network) => network.contains(addr));
  }

  /// Checks a textual address against trusted proxy networks.
  ///
  /// Portable hosts cannot construct [InternetAddress] values, so their
  /// adapters use this path instead.
  bool isTrustedProxyText(String address) {
    if (!features.enableProxySupport) {
      throw StateError(
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    return _parsedProxyNetworks.any((network) => network.containsText(address));
  }

  /// The configured trusted proxy network strings.
  List<String> get trustedProxies {
    return _trustedProxies;
  }

  /// Replaces the trusted proxy networks and clears the parsed cache.
  set trustedProxies(List<String> value) {
    if (!features.enableProxySupport) {
      throw StateError(
        'Proxy support not enabled. Enable with EngineFeatures.enableProxySupport',
      );
    }
    _trustedProxies = value;
    _parsedProxyNetworks = [];
    _trustedProxiesParsed = false;
  }

  /// The configured platform name used for trusted client-address headers.
  /// The platform whose forwarded client-IP headers are trusted.
  String? get trustedPlatform => _trustedPlatform;

  /// Sets the platform whose forwarded client-IP headers are trusted.
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
    int? pathInternCacheSize,
    bool? forwardedByClientIP,
    List<String>? remoteIPHeaders,
    List<String>? trustedProxies,
    String? trustedPlatform,
    String? templateDirectory,
    dynamic templateEngine,
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
      pathInternCacheSize: pathInternCacheSize ?? this.pathInternCacheSize,
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

    // Copy over parsed proxy networks when they are already available.
    if (trustedProxies == null && _trustedProxiesParsed) {
      newConfig._parsedProxyNetworks = List.from(_parsedProxyNetworks);
      newConfig._trustedProxiesParsed = true;
    }

    return newConfig;
  }

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      security.maxRequestSize > 0,
      'security.maxRequestSize',
      'must be greater than zero',
    );
    context.require(
      pathInternCacheSize > 0,
      'pathInternCacheSize',
      'must be greater than zero',
    );
    context.require(
      shutdown.gracePeriod >= Duration.zero,
      'shutdown.gracePeriod',
      'cannot be negative',
    );
    context.require(
      shutdown.forceAfter >= Duration.zero,
      'shutdown.forceAfter',
      'cannot be negative',
    );
    context.require(
      shutdown.forceAfter >= shutdown.gracePeriod,
      'shutdown.forceAfter',
      'must be at least as long as shutdown.gracePeriod',
    );
    context.require(
      !features.enableTrustedPlatform ||
          (trustedPlatform != null && trustedPlatform!.trim().isNotEmpty),
      'trustedPlatform',
      'must be provided when trusted platform support is enabled',
    );
    context.require(
      !features.enableProxySupport || trustedProxies.isNotEmpty,
      'trustedProxies',
      'must contain at least one network when proxy support is enabled',
    );
    context.require(
      security.cors.maxAge == null || security.cors.maxAge! >= 0,
      'security.cors.maxAge',
      'cannot be negative',
    );
    context.require(
      http2.maxConcurrentStreams == null || http2.maxConcurrentStreams! > 0,
      'http2.maxConcurrentStreams',
      'must be greater than zero when provided',
    );
    multipart.validate(context);
  }
}
