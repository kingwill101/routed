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
        path: 'http.middleware_sources',
        type: 'map',
        description: 'Compression middleware references registered globally.',
        defaultValue: <String, Object?>{
          'routed.compression': <String, Object?>{
            'global': <String>['routed.compression.middleware'],
          },
        },
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
    final enabled = config.getBool('compression.enabled', defaultValue: true);

    final minLength = config.getInt('compression.min_length', defaultValue: 1024);
    
    final algorithmNames = config.getStringListOrNull('compression.algorithms') ?? _defaultAlgorithms;

    final algorithms = algorithmNames
        .map(parseCompressionAlgorithm)
        .whereType<CompressionAlgorithm>()
        .where(isAlgorithmSupported)
        .toList(growable: false);

    final allowList = config.getStringListOrNull('compression.mime_allow') ?? _defaultMimeAllow;

    final denyList = config.getStringListOrNull('compression.mime_deny') ?? _defaultMimeDeny;

    return CompressionOptions(
      enabled: enabled && algorithms.isNotEmpty,
      minLength: minLength,
      algorithms: algorithms,
      mimeAllow: allowList,
      mimeDeny: denyList,
    );
  }
}
