import 'package:collection/collection.dart';
import 'package:routed/middlewares.dart' show corsMiddleware;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/config/specs/cors.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';

/// Provides CORS defaults and hooks into middleware configuration.
class CorsServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  Engine? _engine;

  static const _listEquality = ListEquality<String>();
  static const CorsConfigSpec spec = CorsConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.cors': {
          'global': ['routed.cors'],
        },
      },
    };
    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'CORS middleware references injected into the pipeline.',
          defaultValue: <String, Object?>{
            'routed.cors': <String, Object?>{
              'global': <String>['routed.cors'],
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
    registry.register('routed.cors', (_) => corsMiddleware());

    if (!container.has<Config>() || !container.has<EngineConfig>()) {
      return;
    }

    final appConfig = container.get<Config>();
    final engineConfig = container.get<EngineConfig>();
    final resolved = spec.resolveFromConfig(
      appConfig,
      existing: engineConfig.security.cors,
    );

    if (_corsEquals(engineConfig.security.cors, resolved)) {
      return;
    }

    if (container.has<Engine>()) {
      final engine = container.get<Engine>();
      _applyCorsConfig(engine, appConfig);
    } else {
      container.instance<EngineConfig>(
        engineConfig.copyWith(
          security: engineConfig.security.copyWith(cors: resolved),
        ),
      );
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }

    if (container.has<Engine>()) {
      _engine = await container.make<Engine>();
      _applyCorsConfig(_engine!, container.get<Config>());
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final engine =
        _engine ??
        (container.has<Engine>() ? await container.make<Engine>() : null);
    if (engine != null) {
      _applyCorsConfig(engine, config);
    }
  }

  void _applyCorsConfig(Engine engine, Config config) {
    final current = engine.config;
    final resolved = spec.resolveFromConfig(
      config,
      existing: current.security.cors,
    );
    if (_corsEquals(current.security.cors, resolved)) {
      return;
    }

    engine.updateConfig(
      current.copyWith(security: current.security.copyWith(cors: resolved)),
    );
  }

  bool _corsEquals(CorsConfig a, CorsConfig b) {
    return a.enabled == b.enabled &&
        _listEquality.equals(a.allowedOrigins, b.allowedOrigins) &&
        _listEquality.equals(a.allowedMethods, b.allowedMethods) &&
        _listEquality.equals(a.allowedHeaders, b.allowedHeaders) &&
        a.allowCredentials == b.allowCredentials &&
        a.maxAge == b.maxAge &&
        _listEquality.equals(a.exposedHeaders, b.exposedHeaders);
  }
}
