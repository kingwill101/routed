import 'dart:io';

import 'package:es_compression/brotli.dart' as es_brotli;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

typedef CompressionOptionsResolver = CompressionOptions Function();

const String compressionSkipAttribute = '__compression.skip';

/// Marks the current request so the compression middleware skips encoding.
void disableCompression(EngineContext ctx) {
  ctx.request.setAttribute(compressionSkipAttribute, true);
}

/// Clears compression skip flags for the current request.
void enableCompression(EngineContext ctx) {
  ctx.request.setAttribute(compressionSkipAttribute, false);
}

Middleware compressionMiddleware(CompressionOptionsResolver resolver) {
  return (ctx, next) async {
    final options = resolver();
    if (!options.enabled) {
      return await next();
    }

    if (ctx.request.getAttribute<bool>(compressionSkipAttribute) == true) {
      return await next();
    }

    final negotiation = _negotiateEncoding(ctx, options);
    if (negotiation == null) {
      return await next();
    }

    _ensureVaryHeader(ctx);

    ctx.response.setBodyFilter((body) {
      if (ctx.request.getAttribute<bool>(compressionSkipAttribute) == true) {
        return body;
      }

      if (ctx.response.statusCode < 200 ||
          ctx.response.statusCode == HttpStatus.noContent ||
          ctx.response.statusCode == HttpStatus.resetContent ||
          ctx.response.statusCode == HttpStatus.notModified ||
          ctx.request.method == 'HEAD' ||
          body.isEmpty) {
        return body;
      }

      final existingEncoding = ctx.response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (existingEncoding != null && existingEncoding.isNotEmpty) {
        return body;
      }

      final mimeType =
          ctx.response.headers.contentType?.mimeType ??
          ctx.response.headers.value(HttpHeaders.contentTypeHeader) ??
          'text/plain';
      if (!options.isMimeAllowed(mimeType)) {
        return body;
      }

      if (body.length < options.minLength) {
        return body;
      }

      ctx.response.removeHeader(HttpHeaders.contentLengthHeader);
      ctx.response.headers.set(
        HttpHeaders.contentEncodingHeader,
        negotiation.headerValue,
      );

      return negotiation.encode(body);
    });

    return await next();
  };
}

void _ensureVaryHeader(EngineContext ctx) {
  final headerValues = ctx.response.headers[HttpHeaders.varyHeader];
  if (headerValues == null ||
      !headerValues.any(
        (value) => value
            .split(',')
            .map((v) => v.trim().toLowerCase())
            .contains('accept-encoding'),
      )) {
    ctx.response.headers.add('Vary', 'Accept-Encoding');
  }
}

_NegotiatedEncoding? _negotiateEncoding(
  EngineContext ctx,
  CompressionOptions options,
) {
  if (!options.enabled) {
    return null;
  }

  final accept =
      ctx.request.headers[HttpHeaders.acceptEncodingHeader]?.join(',') ?? '';
  if (accept.isEmpty) {
    return null;
  }

  final encodings = _parseAcceptEncoding(accept);
  if (encodings.isEmpty) {
    return null;
  }

  for (final candidate in encodings) {
    if (candidate.q == 0) {
      continue;
    }
    if (candidate.name == '*' && options.algorithms.isNotEmpty) {
      return _NegotiatedEncoding(options.algorithms.first);
    }
    final algorithm = parseCompressionAlgorithm(candidate.name);
    if (algorithm == null) {
      continue;
    }
    if (!isAlgorithmSupported(algorithm)) {
      continue;
    }
    if (!options.algorithms.contains(algorithm)) {
      continue;
    }
    return _NegotiatedEncoding(algorithm);
  }

  return null;
}

List<_AcceptEncoding> _parseAcceptEncoding(String header) {
  final parts = header.split(',');
  final results = <_AcceptEncoding>[];

  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final segments = trimmed.split(';');
    final name = segments.first.trim().toLowerCase();
    double q = 1.0;
    for (final seg in segments.skip(1)) {
      final kv = seg.split('=');
      if (kv.length == 2 && kv.first.trim() == 'q') {
        final value = double.tryParse(kv.last.trim());
        if (value != null) {
          q = value;
        }
      }
    }
    results.add(_AcceptEncoding(name, q));
  }

  results.sort((a, b) => b.q.compareTo(a.q));
  return results;
}

class _AcceptEncoding {
  const _AcceptEncoding(this.name, this.q);

  final String name;
  final double q;
}

class _NegotiatedEncoding {
  _NegotiatedEncoding(this.algorithm);

  final CompressionAlgorithm algorithm;

  String get headerValue {
    switch (algorithm) {
      case CompressionAlgorithm.gzip:
        return 'gzip';
      case CompressionAlgorithm.brotli:
        return 'br';
    }
  }

  List<int> encode(List<int> body) {
    switch (algorithm) {
      case CompressionAlgorithm.gzip:
        return GZipCodec().encode(body);
      case CompressionAlgorithm.brotli:
        return es_brotli.brotli.encode(body);
    }
  }
}

enum CompressionAlgorithm { gzip, brotli }

CompressionAlgorithm? parseCompressionAlgorithm(String value) {
  switch (value.toLowerCase()) {
    case 'gzip':
      return CompressionAlgorithm.gzip;
    case 'br':
    case 'brotli':
      return CompressionAlgorithm.brotli;
    default:
      return null;
  }
}

bool isAlgorithmSupported(CompressionAlgorithm algorithm) {
  switch (algorithm) {
    case CompressionAlgorithm.gzip:
      return true;
    case CompressionAlgorithm.brotli:
      return _isBrotliSupported();
  }
}

bool _isBrotliSupported() {
  if (_brotliSupportChecked) {
    return _brotliSupported;
  }
  _brotliSupportChecked = true;
  try {
    es_brotli.brotli.encode(const [0]);
    _brotliSupported = true;
  } catch (_) {
    _brotliSupported = false;
  }
  return _brotliSupported;
}

bool _brotliSupportChecked = false;
bool _brotliSupported = false;

class CompressionOptions {
  CompressionOptions({
    required this.enabled,
    required this.minLength,
    required List<CompressionAlgorithm> algorithms,
    required List<String> mimeAllow,
    required List<String> mimeDeny,
  }) : algorithms = List<CompressionAlgorithm>.unmodifiable(algorithms),
       _mimeAllow = mimeAllow.map((value) => value.toLowerCase()).toList(),
       _mimeDeny = mimeDeny.map((value) => value.toLowerCase()).toList();

  final bool enabled;
  final int minLength;
  final List<CompressionAlgorithm> algorithms;
  final List<String> _mimeAllow;
  final List<String> _mimeDeny;

  bool isMimeAllowed(String mimeType) {
    final lowered = mimeType.toLowerCase();
    for (final pattern in _mimeDeny) {
      if (_matchesMimePattern(lowered, pattern)) {
        return false;
      }
    }

    if (_mimeAllow.isEmpty) {
      return true;
    }

    for (final pattern in _mimeAllow) {
      if (_matchesMimePattern(lowered, pattern)) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesMimePattern(String mime, String pattern) {
    if (pattern.endsWith('/*')) {
      final prefix = pattern.substring(0, pattern.length - 2);
      return mime.startsWith(prefix);
    }
    return mime == pattern;
  }
}
