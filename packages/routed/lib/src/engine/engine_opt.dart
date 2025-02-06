import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/render/html/template_engine.dart';
import 'package:routed/src/router/types.dart';

/// Function type for engine options.
typedef EngineOpt = void Function(Engine engine);

/// Sets the trusted proxy configuration.
EngineOpt withTrustedProxies(List<String> proxies) {
  return (Engine engine) {
    engine.config.trustedProxies = proxies;
  };
}

/// Sets the maximum request body size.
EngineOpt withMaxRequestSize(int maxSize) {
  return (Engine engine) {
    // engine.config.maxRequestSize = maxSize.
  };
}

/// Enables or disables trailing slash redirects.
EngineOpt withRedirectTrailingSlash(bool enable) {
  return (Engine engine) {
    engine.config.redirectTrailingSlash = enable;
  };
}

/// Enables or disables method not allowed handling.
EngineOpt withHandleMethodNotAllowed(bool enable) {
  return (Engine engine) {
    engine.config.handleMethodNotAllowed = enable;
  };
}

/// Sets global middleware.
EngineOpt withMiddleware(List<Middleware> middleware) {
  return (Engine engine) {
    engine.middlewares.addAll(middleware);
  };
}

/// Sets the template engine.
EngineOpt withTemplateEngine(TemplateEngine templateEngine) {
  return (Engine engine) {
    engine.config.templateEngine = templateEngine;
  };
}

/// Configures multipart settings.
EngineOpt withMultipart({
  int? maxMemory,
  int? maxFileSize,
  Set<String>? allowedExtensions,
}) {
  return (Engine engine) {
    if (maxMemory != null) {
      engine.config.multipart.maxMemory = maxMemory;
    }
    if (maxFileSize != null) {
      engine.config.multipart.maxFileSize = maxFileSize;
    }
    if (allowedExtensions != null) {
      engine.config.multipart.allowedExtensions = allowedExtensions;
    }
  };
}

/// Sets the cache manager.
EngineOpt withCacheManager(CacheManager cacheManager) {
  return (Engine engine) {
    engine.config.cacheManager = cacheManager;
  };
}

EngineOpt withSessionConfig(SessionConfig config) {
  return (Engine engine) {
    engine.config.sessionConfig = config;
  };
}
