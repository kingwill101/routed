import 'package:routed/src/container/container.dart';
import 'package:routed/src/config/specs/compression.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';

import '../../middleware/compression.dart';

class CompressionServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  CompressionOptions? _options;
  static const CompressionConfigSpec spec = CompressionConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.compression': {
          'global': ['routed.compression.middleware'],
        },
      },
    };
    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Compression middleware references registered globally.',
          defaultValue: <String, Object?>{
            'routed.compression': <String, Object?>{
              'global': <String>['routed.compression.middleware'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
    );
  }

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
    final resolved = spec.resolve(config);
    return resolved.toOptions();
  }
}
