import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/security/trusted_proxy_resolver.dart';

/// Function type for engine configuration options.
///
/// Engine options are functions that accept an [Engine] instance and configure
/// it by modifying its settings. They run immediately after the engine is
/// constructed—before built-in service providers finish booting—so they're a
/// convenient hook for tasks such as registering custom locale resolvers,
/// seeding registries, or overriding provider defaults.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withTrustedProxies(['192.168.1.1']),
///     withMaxRequestSize(10 * 1024 * 1024),
///   ],
/// );
/// ```
///
/// ```dart
/// final engine = Engine(
///   options: [
///     (engine) {
///       final registry = engine.container.get<LocaleResolverRegistry>();
///       registry.register('preview', (_) => PreviewResolver());
///     },
///   ],
/// );
/// ```
typedef EngineOpt = void Function(Engine engine);

/// Configures trusted proxy settings for the engine.
///
/// When your application runs behind a proxy or load balancer, this option
/// enables the engine to correctly identify the client's real IP address from
/// proxy headers like `X-Forwarded-For`.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withTrustedProxies([
///       '192.168.1.1',
///       '10.0.0.0/8',
///       '172.16.0.0/12',
///     ]),
///   ],
/// );
/// ```
EngineOpt withTrustedProxies(List<String> proxies) {
  return (Engine engine) {
    engine.appConfig.set('security.trusted_proxies.enabled', true);
    engine.appConfig.set('security.trusted_proxies.forward_client_ip', true);
    engine.appConfig.set('security.trusted_proxies.proxies', proxies);
    if (engine.container.has<TrustedProxyResolver>()) {
      engine.container.get<TrustedProxyResolver>().update(
        enabled: true,
        forwardClientIp: true,
        proxies: proxies,
      );
    }
  };
}

/// Sets the maximum allowed request body size in bytes.
///
/// This option limits how much data can be sent in a single HTTP request body,
/// helping protect against denial-of-service attacks and excessive memory usage.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withMaxRequestSize(5 * 1024 * 1024), // 5MB limit
///   ],
/// );
/// ```
EngineOpt withMaxRequestSize(int maxSize) {
  return (Engine engine) {
    engine.appConfig.set('security.max_request_size', maxSize);
  };
}

/// Configures automatic trailing slash redirects.
///
/// When enabled, requests to `/path` will redirect to `/path/` (and vice versa)
/// if only one version of the route is defined. This helps maintain consistent
/// URL structure.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withRedirectTrailingSlash(true),
///   ],
/// );
/// ```
EngineOpt withRedirectTrailingSlash(bool enable) {
  return (Engine engine) {
    engine.appConfig.set('routing.redirect_trailing_slash', enable);
  };
}

/// Configures handling of HTTP 405 Method Not Allowed responses.
///
/// When enabled, if a route path matches but the HTTP method doesn't, the
/// engine returns a 405 Method Not Allowed response instead of 404 Not Found.
/// The response includes an `Allow` header listing the supported methods.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withHandleMethodNotAllowed(true),
///   ],
/// );
/// ```
EngineOpt withHandleMethodNotAllowed(bool enable) {
  return (Engine engine) {
    engine.appConfig.set('routing.handle_method_not_allowed', enable);
  };
}

/// Configures default logging settings for the engine.
///
/// This option allows customization of request/response logging behavior,
/// including log level, which headers to log, and additional context fields.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withLogging(
///       enabled: true,
///       level: 'info',
///       requestHeaders: ['User-Agent', 'Content-Type'],
///       extraFields: {'service': 'api'},
///     ),
///   ],
/// );
/// ```
EngineOpt withLogging({
  bool? enabled,
  String? level,
  bool? errorsOnly,
  Map<String, dynamic>? extraFields,
  List<String>? requestHeaders,
}) {
  return (Engine engine) {
    if (enabled != null) {
      engine.appConfig.set('logging.enabled', enabled);
    }
    if (level != null && enabled == true) {
      engine.appConfig.set('logging.level', level);
    }
    if (errorsOnly != null && enabled == true) {
      engine.appConfig.set('logging.errors_only', errorsOnly);
    }
    if (extraFields != null) {
      engine.appConfig.set(
        'logging.extra_fields',
        Map<String, dynamic>.from(extraFields),
      );
    }
    if (requestHeaders != null) {
      engine.appConfig.set(
        'logging.request_headers',
        List<String>.from(requestHeaders),
      );
    }
  };
}

/// Configures Cross-Origin Resource Sharing (CORS) settings.
///
/// CORS controls which domains can make cross-origin requests to your API.
/// This is essential for web applications that need to access your API from
/// different domains.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withCors(
///       enabled: true,
///       allowedOrigins: ['https://example.com'],
///       allowedMethods: ['GET', 'POST', 'PUT'],
///       allowedHeaders: ['Content-Type', 'Authorization'],
///       allowCredentials: true,
///       maxAge: 3600,
///     ),
///   ],
/// );
/// ```
EngineOpt withCors({
  bool? enabled,
  List<String>? allowedOrigins,
  List<String>? allowedMethods,
  List<String>? allowedHeaders,
  bool? allowCredentials,
  int? maxAge,
  List<String>? exposedHeaders,
}) {
  return (Engine engine) {
    if (enabled != null) {
      engine.appConfig.set('cors.enabled', enabled);
    }
    if (allowedOrigins != null) {
      engine.appConfig.set('cors.allowed_origins', List.of(allowedOrigins));
    }
    if (allowedMethods != null) {
      engine.appConfig.set('cors.allowed_methods', List.of(allowedMethods));
    }
    if (allowedHeaders != null) {
      engine.appConfig.set('cors.allowed_headers', List.of(allowedHeaders));
    }
    if (allowCredentials != null) {
      engine.appConfig.set('cors.allow_credentials', allowCredentials);
    }
    if (maxAge != null) {
      engine.appConfig.set('cors.max_age', maxAge);
    }
    if (exposedHeaders != null) {
      engine.appConfig.set('cors.exposed_headers', List.of(exposedHeaders));
    }
  };
}

/// Configures static file serving for assets like images, CSS, and JavaScript.
///
/// This option allows you to serve static files from directories or disk
/// storage. You can configure multiple mount points, each serving files from
/// a different source.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withStaticAssets(
///       enabled: true,
///       route: '/assets',
///       directory: 'public/assets',
///       indexFile: 'index.html',
///       listDirectories: false,
///     ),
///   ],
/// );
/// ```
EngineOpt withStaticAssets({
  bool? enabled,
  String? route,
  String? directory,
  String? disk,
  String? path,
  String? indexFile,
  bool? listDirectories,
  List<Map<String, dynamic>>? mounts,
}) {
  return (Engine engine) {
    if (enabled != null) {
      engine.appConfig.set('static.enabled', enabled);
    }
    if (mounts != null) {
      engine.appConfig.set('static.mounts', mounts);
      return;
    }
    if (disk != null || directory != null) {
      final mount = <String, dynamic>{'route': route ?? '/'};
      if (disk != null) {
        mount['disk'] = disk;
      }
      if (path != null) {
        mount['path'] = path;
      } else if (directory != null && disk == null) {
        mount['directory'] = directory;
      }
      if (indexFile != null) {
        mount['index'] = indexFile;
      }
      if (listDirectories != null) {
        mount['list_directories'] = listDirectories;
      }
      engine.appConfig.set('static.mounts', [mount]);
    }
  };
}

/// Registers global middleware to be applied to all routes.
///
/// Global middleware is executed for every request before any route-specific
/// middleware. This is useful for cross-cutting concerns like logging,
/// authentication, or request timing.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withMiddleware([
///       LoggingMiddleware(),
///       CompressionMiddleware(),
///     ]),
///   ],
/// );
/// ```
EngineOpt withMiddleware(List<Middleware> middleware) {
  return (Engine engine) {
    engine.middlewares.addAll(middleware);
  };
}

/// Configures settings for handling multipart form data and file uploads.
///
/// This option controls limits on file uploads including maximum file size,
/// memory usage, and which file extensions are allowed.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withMultipart(
///       maxMemory: 32 * 1024 * 1024, // 32MB
///       maxFileSize: 10 * 1024 * 1024, // 10MB
///       allowedExtensions: {'jpg', 'png', 'pdf'},
///     ),
///   ],
/// );
/// ```
EngineOpt withMultipart({
  int? maxMemory,
  int? maxFileSize,
  Set<String>? allowedExtensions,
}) {
  return (Engine engine) {
    if (maxMemory != null) {
      engine.appConfig.set('uploads.max_memory', maxMemory);
    }
    if (maxFileSize != null) {
      engine.appConfig.set('uploads.max_file_size', maxFileSize);
    }
    if (allowedExtensions != null) {
      engine.appConfig.set(
        'uploads.allowed_extensions',
        allowedExtensions.toList(),
      );
    }
  };
}

/// Registers a custom cache manager for the engine.
///
/// The cache manager handles caching of responses, compiled templates, and
/// other cacheable data. Provide your own implementation to customize caching
/// behavior.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withCacheManager(
///       RedisCacheManager(host: 'localhost', port: 6379),
///     ),
///   ],
/// );
/// ```
EngineOpt withCacheManager(CacheManager cacheManager) {
  return (Engine engine) {
    engine.container.instance<CacheManager>(cacheManager);
  };
}

/// Configures session management settings.
///
/// Sessions allow you to store user-specific data across multiple requests.
/// This option configures how sessions are stored, their lifetime, and
/// security settings.
///
/// Example:
/// ```dart
/// final engine = Engine(
///   options: [
///     withSessionConfig(
///       SessionConfig(
///         driver: 'cookie',
///         lifetime: Duration(hours: 2),
///         secure: true,
///         httpOnly: true,
///       ),
///     ),
///   ],
/// );
/// ```
EngineOpt withSessionConfig(SessionConfig config) {
  return (Engine engine) {
    final appConfig = engine.appConfig;
    appConfig.set('session.config', config);
    engine.container.instance<SessionConfig>(config);
  };
}
