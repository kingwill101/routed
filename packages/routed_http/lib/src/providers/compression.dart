import 'dart:io';

import 'package:routed_core/routed_core.dart';

/// Configuration for the built-in gzip response compression provider.
class CompressionConfig implements ValidatableConfiguration {
  CompressionConfig({
    this.enabled = false,
    this.minLength = 1024,
    List<String>? algorithms,
    List<String>? mimeAllow,
    List<String>? mimeDeny,
  }) : algorithms = List<String>.unmodifiable(algorithms ?? const ['gzip']),
       mimeAllow = List<String>.unmodifiable(
         mimeAllow ??
             const ['text/*', 'application/json', 'application/javascript'],
       ),
       mimeDeny = List<String>.unmodifiable(
         mimeDeny ?? const ['image/*', 'audio/*', 'video/*'],
       );

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

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      minLength >= 0,
      'minLength',
      'minimum response length cannot be negative',
    );
    context.require(
      algorithms.every((algorithm) => algorithm.trim().isNotEmpty),
      'algorithms',
      'compression algorithms cannot contain empty names',
    );
    context.require(
      mimeAllow.every((pattern) => pattern.trim().isNotEmpty),
      'mimeAllow',
      'allowed MIME patterns cannot be empty',
    );
    context.require(
      mimeDeny.every((pattern) => pattern.trim().isNotEmpty),
      'mimeDeny',
      'denied MIME patterns cannot be empty',
    );
  }
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

/// Provider that installs [compressionMiddleware] from [configuration].
class RoutedCompressionProvider extends ServiceProvider
    with ProvidesTypedConfiguration<CompressionConfig> {
  RoutedCompressionProvider([CompressionConfig? configuration])
    : configuration = configuration ?? CompressionConfig();

  @override
  final CompressionConfig configuration;

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    if (!configuration.enabled || !container.has<Engine>()) return;
    container.get<Engine>().middlewares.insert(
      0,
      compressionMiddleware(configuration),
    );
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
