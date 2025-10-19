import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../../middleware/compression.dart';

const _defaultAlgorithms = ['br', 'gzip'];
const _defaultMimeAllow = [
  'text/*',
  'application/json',
  'application/javascript',
];
const _defaultMimeDeny = ['image/*', 'audio/*', 'video/*'];

class CompressionServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  CompressionOptions? _options;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.compression': {
            'global': ['routed.compression.middleware'],
          },
        },
      },
    },
    docs: [
      ConfigDocEntry(
        path: 'compression.enabled',
        type: 'bool',
        description: 'Enable automatic response compression.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'compression.min_length',
        type: 'int',
        description: 'Minimum body size (bytes) before compression applies.',
        defaultValue: 1024,
      ),
      ConfigDocEntry(
        path: 'compression.algorithms',
        type: 'list<string>',
        description: 'Preferred compression algorithms (gzip, br).',
        defaultValue: _defaultAlgorithms,
      ),
      ConfigDocEntry(
        path: 'compression.mime_allow',
        type: 'list<string>',
        description: 'MIME prefixes eligible for compression.',
        defaultValue: _defaultMimeAllow,
      ),
      ConfigDocEntry(
        path: 'compression.mime_deny',
        type: 'list<string>',
        description: 'MIME prefixes excluded from compression.',
        defaultValue: _defaultMimeDeny,
      ),
      ConfigDocEntry(
        path: 'http.features.compression.enabled',
        type: 'bool',
        description: 'Feature toggle for the compression middleware.',
        defaultValue: true,
      ),
    ],
  );

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'routed.compression.middleware',
      (c) => compressionMiddleware(() => _ensureOptions(c)),
    );

    if (container.has<Config>()) {
      final options = _buildOptions(container.get<Config>());
      _options = options;
      container.instance<CompressionOptions>(options);
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }
    final options = _buildOptions(container.get<Config>());
    _options = options;
    container.instance<CompressionOptions>(options);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final options = _buildOptions(config);
    _options = options;
    container.instance<CompressionOptions>(options);
  }

  CompressionOptions _ensureOptions(Container container) {
    if (_options != null) {
      return _options!;
    }
    final config = container.get<Config>();
    final built = _buildOptions(config);
    _options = built;
    container.instance<CompressionOptions>(built);
    return built;
  }

  CompressionOptions _buildOptions(Config config) {
    final enabledFeature =
        parseBoolLike(
          config.get('http.features.compression.enabled'),
          context: 'http.features.compression.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        true;

    final enabled =
        parseBoolLike(
          config.get('compression.enabled'),
          context: 'compression.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        enabledFeature;

    final minLength =
        parseIntLike(
          config.get('compression.min_length'),
          context: 'compression.min_length',
          nonNegative: true,
        ) ??
        1024;

    final algorithmNames =
        parseStringList(
          config.get('compression.algorithms'),
          context: 'compression.algorithms',
          allowEmptyResult: true,
        ) ??
        _defaultAlgorithms;

    final algorithms = algorithmNames
        .map(parseCompressionAlgorithm)
        .whereType<CompressionAlgorithm>()
        .where(isAlgorithmSupported)
        .toList(growable: false);

    final allowList =
        parseStringList(
          config.get('compression.mime_allow'),
          context: 'compression.mime_allow',
          allowEmptyResult: true,
        ) ??
        _defaultMimeAllow;

    final denyList =
        parseStringList(
          config.get('compression.mime_deny'),
          context: 'compression.mime_deny',
          allowEmptyResult: true,
        ) ??
        _defaultMimeDeny;

    return CompressionOptions(
      enabled: enabled && algorithms.isNotEmpty,
      minLength: minLength,
      algorithms: algorithms,
      mimeAllow: allowList,
      mimeDeny: denyList,
    );
  }
}
