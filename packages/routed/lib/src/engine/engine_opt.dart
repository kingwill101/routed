import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/render/html/template_engine.dart';
import 'package:routed/src/router/types.dart';

/// Function type for engine options
typedef EngineOpt = void Function(Engine engine);

/// Creates an option to set the trusted proxy configuration
EngineOpt withTrustedProxies(List<String> proxies) {
  return (Engine engine) {
    engine.config.trustedProxies = proxies;
  };
}

/// Creates an option to set the maximum request body size
EngineOpt withMaxRequestSize(int maxSize) {
  return (Engine engine) {
    // engine.config.maxRequestSize = maxSize;
  };
}

/// Creates an option to enable/disable trailing slash redirects
EngineOpt withRedirectTrailingSlash(bool enable) {
  return (Engine engine) {
    engine.config.redirectTrailingSlash = enable;
  };
}

/// Creates an option to enable/disable method not allowed handling
EngineOpt withHandleMethodNotAllowed(bool enable) {
  return (Engine engine) {
    engine.config.handleMethodNotAllowed = enable;
  };
}

/// Creates an option to set global middleware
EngineOpt withMiddleware(List<Middleware> middleware) {
  return (Engine engine) {
    engine.middlewares.addAll(middleware);
  };
}

/// Creates an option to set the template engine
EngineOpt withTemplateEngine(TemplateEngine templateEngine) {
  return (Engine engine) {
    engine.config.templateEngine = templateEngine;
  };
}

/// Creates an option to configure multipart settings
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
