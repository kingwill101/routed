import 'package:routed/src/middleware/compression.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

const _defaultAlgorithms = ['br', 'gzip'];
const _defaultMimeAllow = [
  'text/*',
  'application/json',
  'application/javascript',
];
const _defaultMimeDeny = ['image/*', 'audio/*', 'video/*'];

class CompressionConfig {
  CompressionConfig({
    required this.enabled,
    required this.minLength,
    required this.algorithms,
    required this.mimeAllow,
    required this.mimeDeny,
  });

  final bool enabled;
  final int minLength;
  final List<CompressionAlgorithm> algorithms;
  final List<String> mimeAllow;
  final List<String> mimeDeny;

  CompressionOptions toOptions() {
    return CompressionOptions(
      enabled: enabled && algorithms.isNotEmpty,
      minLength: minLength,
      algorithms: algorithms,
      mimeAllow: mimeAllow,
      mimeDeny: mimeDeny,
    );
  }
}

class CompressionConfigSpec extends ConfigSpec<CompressionConfig> {
  const CompressionConfigSpec();

  @override
  String get root => 'compression';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'enabled': true,
      'min_length': 1024,
      'algorithms': _defaultAlgorithms,
      'mime_allow': _defaultMimeAllow,
      'mime_deny': _defaultMimeDeny,
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('enabled'),
        type: 'bool',
        description: 'Enable automatic response compression.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('min_length'),
        type: 'int',
        description: 'Minimum body size (bytes) before compression applies.',
        defaultValue: 1024,
      ),
      ConfigDocEntry(
        path: path('algorithms'),
        type: 'list<string>',
        description: 'Preferred compression algorithms (gzip, br).',
        defaultValue: _defaultAlgorithms,
      ),
      ConfigDocEntry(
        path: path('mime_allow'),
        type: 'list<string>',
        description: 'MIME prefixes eligible for compression.',
        defaultValue: _defaultMimeAllow,
      ),
      ConfigDocEntry(
        path: path('mime_deny'),
        type: 'list<string>',
        description: 'MIME prefixes excluded from compression.',
        defaultValue: _defaultMimeDeny,
      ),
    ];
  }

  @override
  CompressionConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'compression.enabled',
          throwOnInvalid: true,
        ) ??
        true;

    final minLength =
        parseIntLike(
          map['min_length'],
          context: 'compression.min_length',
          throwOnInvalid: true,
        ) ??
        1024;

    final algorithmNames =
        parseStringList(
          map['algorithms'],
          context: 'compression.algorithms',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        _defaultAlgorithms;
    final algorithms = algorithmNames
        .map(parseCompressionAlgorithm)
        .whereType<CompressionAlgorithm>()
        .where(isAlgorithmSupported)
        .toList(growable: false);

    final allowList =
        parseStringList(
          map['mime_allow'],
          context: 'compression.mime_allow',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        _defaultMimeAllow;

    final denyList =
        parseStringList(
          map['mime_deny'],
          context: 'compression.mime_deny',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        _defaultMimeDeny;

    return CompressionConfig(
      enabled: enabled && algorithms.isNotEmpty,
      minLength: minLength,
      algorithms: algorithms,
      mimeAllow: allowList,
      mimeDeny: denyList,
    );
  }

  @override
  Map<String, dynamic> toMap(CompressionConfig value) {
    return {
      'enabled': value.enabled,
      'min_length': value.minLength,
      'algorithms':
          value.algorithms.map(_algorithmToken).toList(growable: false),
      'mime_allow': value.mimeAllow,
      'mime_deny': value.mimeDeny,
    };
  }
}

String _algorithmToken(CompressionAlgorithm algorithm) {
  switch (algorithm) {
    case CompressionAlgorithm.gzip:
      return 'gzip';
    case CompressionAlgorithm.brotli:
      return 'br';
  }
}
