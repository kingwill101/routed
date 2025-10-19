import 'package:collection/collection.dart';
import 'package:routed/middlewares.dart' show corsMiddleware;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

/// Provides CORS defaults and hooks into middleware configuration.
class CorsServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  Engine? _engine;

  static const _listEquality = ListEquality<String>();
  static const CorsConfig _defaultCors = CorsConfig();

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.cors': {
            'global': ['routed.cors'],
          },
        },
      },
    },
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'cors.enabled',
        type: 'bool',
        description: 'Enables CORS middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'cors.allowed_origins',
        type: 'list<string>',
        description: 'Origins allowed to access this application.',
        defaultValue: ['*'],
      ),
      ConfigDocEntry(
        path: 'cors.allowed_methods',
        type: 'list<string>',
        description: 'HTTP methods permitted for CORS requests.',
        defaultValue: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      ),
      ConfigDocEntry(
        path: 'cors.allowed_headers',
        type: 'list<string>',
        description: 'Request headers accepted for CORS requests.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'cors.exposed_headers',
        type: 'list<string>',
        description: 'Response headers exposed to the browser.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'cors.allow_credentials',
        type: 'bool',
        description: 'Whether cookies/credentials can be shared cross-origin.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'cors.max_age',
        type: 'int|null',
        description: 'Preflight cache duration in seconds.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'http.features.cors.enabled',
        type: 'bool',
        description: 'Feature toggle for registering the CORS middleware.',
        defaultValue: false,
      ),
    ],
  );

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.cors', (_) => corsMiddleware());

    if (!container.has<Config>() || !container.has<EngineConfig>()) {
      return;
    }

    final appConfig = container.get<Config>();
    final engineConfig = container.get<EngineConfig>();
    final resolved = _resolveCorsConfig(appConfig, engineConfig.security.cors);

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
    final resolved = _resolveCorsConfig(config, current.security.cors);
    if (_corsEquals(current.security.cors, resolved)) {
      return;
    }

    engine.updateConfig(
      current.copyWith(security: current.security.copyWith(cors: resolved)),
    );
  }

  CorsConfig _resolveCorsConfig(Config config, CorsConfig existing) {
    final merged = mergeConfigCandidates([
      ConfigMapCandidate.fromConfig(
        config,
        'security.cors',
        transform: (value) => _corsNodeToMap(value, 'security.cors'),
      ),
      ConfigMapCandidate.fromConfig(
        config,
        'cors',
        transform: (value) => _corsNodeToMap(value, 'cors'),
      ),
    ]);

    if (merged.isNotEmpty && _matchesDefaultCors(merged)) {
      return existing;
    }

    final enabled =
        parseBoolLike(
          merged['enabled'],
          context: 'cors.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        existing.enabled;
    final allowedOrigins =
        parseStringList(
          merged['allowed_origins'],
          context: 'cors.allowed_origins',
        ) ??
        existing.allowedOrigins;
    final allowedMethods =
        parseStringList(
          merged['allowed_methods'],
          context: 'cors.allowed_methods',
        ) ??
        existing.allowedMethods;
    final allowedHeaders =
        parseStringList(
          merged['allowed_headers'],
          context: 'cors.allowed_headers',
        ) ??
        existing.allowedHeaders;
    final allowCredentials =
        parseBoolLike(
          merged['allow_credentials'],
          context: 'cors.allow_credentials',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        existing.allowCredentials;
    final maxAge =
        parseIntLike(merged['max_age'], context: 'cors.max_age') ??
        existing.maxAge;
    final exposedHeaders =
        parseStringList(
          merged['exposed_headers'],
          context: 'cors.exposed_headers',
        ) ??
        existing.exposedHeaders;

    return CorsConfig(
      enabled: enabled,
      allowedOrigins: allowedOrigins,
      allowedMethods: allowedMethods,
      allowedHeaders: allowedHeaders,
      allowCredentials: allowCredentials,
      maxAge: maxAge,
      exposedHeaders: exposedHeaders,
    );
  }

  Map<String, dynamic> _corsNodeToMap(Object value, String context) {
    if (value is CorsConfig) {
      return _corsConfigToMap(value);
    }
    return stringKeyedMap(value, context);
  }

  Map<String, dynamic> _corsConfigToMap(CorsConfig config) {
    return <String, dynamic>{
      'enabled': config.enabled,
      'allowed_origins': config.allowedOrigins,
      'allowed_methods': config.allowedMethods,
      'allowed_headers': config.allowedHeaders,
      'allow_credentials': config.allowCredentials,
      'max_age': config.maxAge,
      'exposed_headers': config.exposedHeaders,
    };
  }

  bool _matchesDefaultCors(Map<String, dynamic> overrides) {
    for (final entry in overrides.entries) {
      final key = entry.key;
      final value = entry.value;
      switch (key) {
        case 'enabled':
          final parsed = parseBoolLike(
            value,
            context: 'cors.enabled',
            stringMappings: const {'true': true, 'false': false},
          );
          if (parsed != null && parsed != _defaultCors.enabled) {
            return false;
          }
          break;
        case 'allow_credentials':
          final parsed = parseBoolLike(
            value,
            context: 'cors.allow_credentials',
            stringMappings: const {'true': true, 'false': false},
          );
          if (parsed != null && parsed != _defaultCors.allowCredentials) {
            return false;
          }
          break;
        case 'allowed_origins':
          final parsed = parseStringList(
            value,
            context: 'cors.allowed_origins',
          );
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedOrigins)) {
            return false;
          }
          break;
        case 'allowed_methods':
          final parsed = parseStringList(
            value,
            context: 'cors.allowed_methods',
          );
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedMethods)) {
            return false;
          }
          break;
        case 'allowed_headers':
          final parsed = parseStringList(
            value,
            context: 'cors.allowed_headers',
          );
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedHeaders)) {
            return false;
          }
          break;
        case 'exposed_headers':
          final parsed = parseStringList(
            value,
            context: 'cors.exposed_headers',
          );
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.exposedHeaders)) {
            return false;
          }
          break;
        case 'max_age':
          final parsed = parseIntLike(value, context: 'cors.max_age');
          if (parsed != _defaultCors.maxAge) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
    return true;
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
