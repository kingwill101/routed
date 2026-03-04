import 'package:es_compression/brotli.dart' as es_brotli;

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

String compressionAlgorithmToken(CompressionAlgorithm algorithm) {
  switch (algorithm) {
    case CompressionAlgorithm.gzip:
      return 'gzip';
    case CompressionAlgorithm.brotli:
      return 'br';
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
