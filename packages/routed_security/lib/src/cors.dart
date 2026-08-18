import 'package:routed_core/routed_core.dart';

/// Applies CORS headers and handles browser preflight requests.
///
/// An absent `Origin` header is treated as a non-browser request and passes
/// through unchanged. A configured wildcard origin is echoed for credentialed
/// requests because browsers reject `Access-Control-Allow-Origin: *` together
/// with `Access-Control-Allow-Credentials: true`.
Middleware corsMiddleware(CorsConfig config) {
  return (ctx, next) async {
    if (!config.enabled) {
      return next();
    }

    final origin = ctx.request.headers.value('Origin');
    if (origin == null || origin.trim().isEmpty) {
      return next();
    }

    final trimmedOrigin = origin.trim();
    final wildcard = config.allowedOrigins.any((item) => item.trim() == '*');
    final allowed =
        wildcard || _containsOrigin(config.allowedOrigins, trimmedOrigin);
    final isPreflight =
        ctx.request.method.toUpperCase() == 'OPTIONS' &&
        ctx.request.headers.value('Access-Control-Request-Method') != null;

    if (!allowed) {
      if (isPreflight) {
        return _reject(ctx, 'CORS origin denied');
      }
      return next();
    }

    final responseOrigin = wildcard && !config.allowCredentials
        ? '*'
        : trimmedOrigin;
    ctx.response.headers.set('Access-Control-Allow-Origin', responseOrigin);
    _appendVary(ctx.response.headers, 'Origin');

    if (config.allowCredentials) {
      ctx.response.headers.set('Access-Control-Allow-Credentials', 'true');
    }
    if (config.exposedHeaders.isNotEmpty) {
      ctx.response.headers.set(
        'Access-Control-Expose-Headers',
        config.exposedHeaders.join(', '),
      );
    }

    if (!isPreflight) {
      return next();
    }

    final requestedMethod = ctx.request.headers
        .value('Access-Control-Request-Method')!
        .trim()
        .toUpperCase();
    final allowedMethods = config.allowedMethods
        .map((method) => method.trim().toUpperCase())
        .where((method) => method.isNotEmpty)
        .toList(growable: false);
    if (!_allowsValue(allowedMethods, requestedMethod)) {
      return _reject(ctx, 'CORS method denied');
    }

    final requestedHeaders = _splitHeaderList(
      ctx.request.headers.value('Access-Control-Request-Headers'),
    );
    final allowedHeaders = config.allowedHeaders
        .map((header) => header.trim().toLowerCase())
        .where((header) => header.isNotEmpty)
        .toList(growable: false);
    if (!_allowsHeaders(allowedHeaders, requestedHeaders)) {
      return _reject(ctx, 'CORS header denied');
    }

    ctx.response.headers.set(
      'Access-Control-Allow-Methods',
      allowedMethods.join(', '),
    );
    if (requestedHeaders.isNotEmpty) {
      ctx.response.headers.set(
        'Access-Control-Allow-Headers',
        allowedHeaders.isEmpty
            ? requestedHeaders.join(', ')
            : allowedHeaders.join(', '),
      );
    }
    if (config.maxAge != null) {
      ctx.response.headers.set('Access-Control-Max-Age', '${config.maxAge}');
    }
    _appendVary(ctx.response.headers, 'Access-Control-Request-Method');
    _appendVary(ctx.response.headers, 'Access-Control-Request-Headers');
    ctx.response.statusCode = HttpStatus.noContent;
    ctx.abort();
    return ctx.response;
  };
}

bool _containsOrigin(List<String> allowedOrigins, String origin) {
  final normalized = origin.toLowerCase();
  return allowedOrigins.any((allowed) {
    final candidate = allowed.trim();
    return candidate.isNotEmpty && candidate.toLowerCase() == normalized;
  });
}

bool _allowsValue(List<String> allowed, String value) {
  return allowed.contains('*') || allowed.contains(value);
}

bool _allowsHeaders(List<String> allowed, List<String> requested) {
  if (requested.isEmpty || allowed.isEmpty || allowed.contains('*')) {
    return true;
  }
  return requested.every((header) => allowed.contains(header.toLowerCase()));
}

List<String> _splitHeaderList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(',')
      .map((header) => header.trim())
      .where((header) => header.isNotEmpty)
      .toList(growable: false);
}

Response _reject(EngineContext ctx, String message) {
  ctx.abortWithStatus(HttpStatus.forbidden, message);
  return ctx.response;
}

void _appendVary(HttpHeaders headers, String value) {
  final existing = headers.value(HttpHeaders.varyHeader);
  if (existing == null || existing.trim().isEmpty) {
    headers.set(HttpHeaders.varyHeader, value);
    return;
  }
  final values = existing.split(',').map((item) => item.trim()).toList();
  if (!values.any((item) => item.toLowerCase() == value.toLowerCase())) {
    values.add(value);
    headers.set(HttpHeaders.varyHeader, values.join(', '));
  }
}
