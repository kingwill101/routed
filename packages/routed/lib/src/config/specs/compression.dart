import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/middleware/compression.dart';
import 'package:routed/src/provider/config_utils.dart';

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
  Schema? get schema => ConfigSchema.object(
    title: 'Compression Configuration',
    description: 'Automatic response compression settings.',
    properties: {
      'enabled': ConfigSchema.boolean(
        description: 'Enable automatic response compression.',
        defaultValue: true,
      ),
      'min_length': ConfigSchema.integer(
        description: 'Minimum body size (bytes) before compression applies.',
        defaultValue: 1024,
      ),
      'algorithms': ConfigSchema.list(
        description: 'Preferred compression algorithms (gzip, br).',
        items: ConfigSchema.string(),
        defaultValue: _defaultAlgorithms,
      ),
      'mime_allow': ConfigSchema.list(
        description: 'MIME prefixes eligible for compression.',
        items: ConfigSchema.string(),
        defaultValue: _defaultMimeAllow,
      ),
      'mime_deny': ConfigSchema.list(
        description: 'MIME prefixes excluded from compression.',
        items: ConfigSchema.string(),
        defaultValue: _defaultMimeDeny,
      ),
    },
  );

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
      'algorithms': value.algorithms
          .map(_algorithmToken)
          .toList(growable: false),
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
