import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// Configuration for the built-in gzip response compression provider.
class CompressionConfig {
  const CompressionConfig({
    this.enabled = false,
    this.minLength = 1024,
    this.algorithms = const ['gzip'],
    this.mimeAllow = const [
      'text/*',
      'application/json',
      'application/javascript',
    ],
    this.mimeDeny = const ['image/*', 'audio/*', 'video/*'],
  });

  /// Whether response compression is enabled.
  final bool enabled;

  /// Minimum buffered response size in bytes before compression is applied.
  final int minLength;

  /// Compression algorithms in preference order. Currently `gzip` is
  /// supported; other names are ignored until their encoders are available.
  final List<String> algorithms;

  /// MIME types eligible for compression. A trailing `*` matches a prefix.
  final List<String> mimeAllow;

  /// MIME types excluded from compression. A trailing `*` matches a prefix.
  final List<String> mimeDeny;
}

/// Compresses eligible buffered responses when the client accepts gzip.
///
/// Streaming responses are left untouched because [Response.addStream] and
/// [Response.flush] bypass the buffered body filter. Existing encodings,
/// status-only responses, and denied MIME types are also left unchanged.
Middleware compressionMiddleware(CompressionConfig config) {
  return (ctx, next) {
    if (!config.enabled || !_supportsGzip(config.algorithms)) {
      return next();
    }

    final quality = _gzipQuality(
      ctx.request.headers.value(HttpHeaders.acceptEncodingHeader),
    );
    if (quality <= 0 || ctx.method.toUpperCase() == 'HEAD') {
      return next();
    }

    ctx.response.setBodyFilter((body) {
      if (body.length < config.minLength ||
          ctx.response.statusCode == HttpStatus.noContent ||
          ctx.response.statusCode == HttpStatus.notModified ||
          ctx.response.headerValue(HttpHeaders.contentEncodingHeader) != null) {
        return body;
      }

      final contentType = ctx.response.headerValue(
        HttpHeaders.contentTypeHeader,
      );
      if (!_allowsMime(contentType, config)) return body;

      ctx.response.removeHeader(HttpHeaders.contentLengthHeader);
      ctx.response.setHeader(HttpHeaders.contentEncodingHeader, 'gzip');
      _appendVary(ctx.response, HttpHeaders.acceptEncodingHeader);
      return gzip.encode(body);
    });

    return next();
  };
}

/// Provider that installs [compressionMiddleware] from `compression.*` config.
class RoutedCompressionProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  Middleware? _middleware;

  @override
  void register(Container container) {}

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    values: {
      'compression': {
        'enabled': false,
        'min_length': 1024,
        'algorithms': ['gzip'],
        'mime_allow': ['text/*', 'application/json', 'application/javascript'],
        'mime_deny': ['image/*', 'audio/*', 'video/*'],
      },
    },
    docs: const [
      ConfigDocEntry(
        path: 'compression',
        type: 'map',
        description: 'Gzip response compression for buffered responses.',
      ),
    ],
  );

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>() || !container.has<Config>()) return;
    _apply(container.get<Engine>(), container.get<Config>());
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    if (!container.has<Engine>()) return;
    _apply(container.get<Engine>(), config);
  }

  void _apply(Engine engine, Config config) {
    final existing = _middleware;
    if (existing != null) {
      engine.middlewares.removeWhere(
        (middleware) => identical(middleware, existing),
      );
      _middleware = null;
    }

    final settings = CompressionConfig(
      enabled: config.getBoolOrNull('compression.enabled') ?? false,
      minLength: config.getIntOrNull('compression.min_length') ?? 1024,
      algorithms:
          config.getStringListOrNull('compression.algorithms') ??
          const ['gzip'],
      mimeAllow:
          config.getStringListOrNull('compression.mime_allow') ??
          const ['text/*', 'application/json', 'application/javascript'],
      mimeDeny:
          config.getStringListOrNull('compression.mime_deny') ??
          const ['image/*', 'audio/*', 'video/*'],
    );
    if (!settings.enabled) {
      engine.updateConfig(engine.config);
      return;
    }

    final middleware = compressionMiddleware(settings);
    _middleware = middleware;
    engine.middlewares.insert(0, middleware);
    engine.updateConfig(engine.config);
  }
}

bool _supportsGzip(List<String> algorithms) =>
    algorithms.any((algorithm) => algorithm.trim().toLowerCase() == 'gzip');

double _gzipQuality(String? header) {
  if (header == null || header.trim().isEmpty) return 0;
  double? wildcard;
  double? explicit;
  for (final item in header.split(',')) {
    final parts = item.trim().split(';');
    final encoding = parts.first.trim().toLowerCase();
    var quality = 1.0;
    for (final parameter in parts.skip(1)) {
      final pair = parameter.split('=');
      if (pair.length == 2 && pair.first.trim().toLowerCase() == 'q') {
        quality = double.tryParse(pair.last.trim()) ?? 0;
      }
    }
    if (encoding == 'gzip') {
      explicit = quality;
    } else if (encoding == '*') {
      wildcard = quality;
    }
  }
  return explicit ?? wildcard ?? 0;
}

bool _allowsMime(String? contentType, CompressionConfig config) {
  if (contentType == null || contentType.trim().isEmpty) return false;
  final mime = contentType.split(';').first.trim().toLowerCase();
  if (_matchesMime(config.mimeDeny, mime)) return false;
  return _matchesMime(config.mimeAllow, mime);
}

bool _matchesMime(Iterable<String> patterns, String mime) {
  return patterns.any((pattern) {
    final normalized = pattern.trim().toLowerCase();
    if (normalized.endsWith('*')) {
      return mime.startsWith(normalized.substring(0, normalized.length - 1));
    }
    return mime == normalized;
  });
}

void _appendVary(Response response, String value) {
  final existing = response.headerValue(HttpHeaders.varyHeader);
  if (existing == null || existing.trim().isEmpty) {
    response.setHeader(HttpHeaders.varyHeader, value);
    return;
  }
  final values = existing.split(',').map((item) => item.trim()).toList();
  if (!values.any((item) => item.toLowerCase() == value.toLowerCase())) {
    values.add(value);
    response.setHeader(HttpHeaders.varyHeader, values.join(', '));
  }
}
