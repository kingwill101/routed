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
        path: 'http.middleware_sources',
        type: 'map',
        description: 'CORS middleware references injected into the pipeline.',
        defaultValue: <String, Object?>{
          'routed.cors': <String, Object?>{
            'global': <String>['routed.cors'],
          },
        },
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

    // Validate config values first - throw on invalid types before any other checks
    _validateCorsConfig(merged);

    if (merged.isNotEmpty && _matchesDefaultCors(merged)) {
      return existing;
    }

    final enabled = merged.getBool('enabled', defaultValue: existing.enabled);
    final allowedOrigins =
        merged.getStringList('allowed_origins') ?? existing.allowedOrigins;
    final allowedMethods =
        merged.getStringList('allowed_methods') ?? existing.allowedMethods;
    final allowedHeaders =
        merged.getStringList('allowed_headers') ?? existing.allowedHeaders;
    final allowCredentials = merged.getBool(
      'allow_credentials',
      defaultValue: existing.allowCredentials,
    );
    final maxAge = merged.getInt('max_age') ?? existing.maxAge;
    final exposedHeaders =
        merged.getStringList('exposed_headers') ?? existing.exposedHeaders;

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
          final parsed = {key: value}.getBool(key);
          if (parsed != _defaultCors.enabled) {
            return false;
          }
          break;
        case 'allow_credentials':
          final parsed = {key: value}.getBool(key);
          if (parsed != _defaultCors.allowCredentials) {
            return false;
          }
          break;
        case 'allowed_origins':
          final parsed = {key: value}.getStringList(key);
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedOrigins)) {
            return false;
          }
          break;
        case 'allowed_methods':
          final parsed = {key: value}.getStringList(key);
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedMethods)) {
            return false;
          }
          break;
        case 'allowed_headers':
          final parsed = {key: value}.getStringList(key);
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.allowedHeaders)) {
            return false;
          }
          break;
        case 'exposed_headers':
          final parsed = {key: value}.getStringList(key);
          if (parsed != null &&
              !_listEquality.equals(parsed, _defaultCors.exposedHeaders)) {
            return false;
          }
          break;
        case 'max_age':
          final parsed = {key: value}.getInt(key);
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

  /// Validates CORS config values, throwing if types are wrong.
  void _validateCorsConfig(Map<String, dynamic> merged) {
    // Re-key with 'cors.' prefix for error messages
    final prefixed = merged.map((k, v) => MapEntry('cors.$k', v));

    // Validate 'enabled' if present
    if (merged.containsKey('enabled')) {
      prefixed.getBoolOrThrow('cors.enabled');
    }

    // Validate 'allow_credentials' if present
    if (merged.containsKey('allow_credentials')) {
      prefixed.getBoolOrThrow('cors.allow_credentials');
    }

    // Validate list fields if present
    if (merged.containsKey('allowed_origins')) {
      prefixed.getStringListOrThrow('cors.allowed_origins');
    }

    if (merged.containsKey('allowed_methods')) {
      prefixed.getStringListOrThrow('cors.allowed_methods');
    }

    if (merged.containsKey('allowed_headers')) {
      prefixed.getStringListOrThrow('cors.allowed_headers');
    }

    if (merged.containsKey('exposed_headers')) {
      prefixed.getStringListOrThrow('cors.exposed_headers');
    }

    // Validate 'max_age' if present
    if (merged.containsKey('max_age')) {
      prefixed.getIntOrThrow('cors.max_age');
    }
  }
}
