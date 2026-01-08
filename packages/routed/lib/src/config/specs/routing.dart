import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/engine/config.dart' show EngineConfig, EtagStrategy;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class RoutingConfig {
  const RoutingConfig({
    required this.redirectTrailingSlash,
    required this.handleMethodNotAllowed,
    required this.defaultOptionsEnabled,
    required this.etagStrategy,
  });

  factory RoutingConfig.fromMap(Map<String, dynamic> map) {
    final redirectTrailingSlash =
        parseBoolLike(
          map['redirect_trailing_slash'],
          context: 'routing.redirect_trailing_slash',
          throwOnInvalid: true,
        ) ??
        true;

    final handleMethodNotAllowed =
        parseBoolLike(
          map['handle_method_not_allowed'],
          context: 'routing.handle_method_not_allowed',
          throwOnInvalid: true,
        ) ??
        true;

    final defaultOptionsEnabled =
        parseBoolLike(
          map['default_options'],
          context: 'routing.default_options',
          throwOnInvalid: true,
        ) ??
        true;

    final etagRaw = map['etag'];
    final etagMap = etagRaw == null
        ? const <String, dynamic>{}
        : stringKeyedMap(etagRaw as Object, 'routing.etag');

    final etagStrategy = parseEtagStrategy(
      etagMap['strategy'],
      context: 'routing.etag.strategy',
    );

    return RoutingConfig(
      redirectTrailingSlash: redirectTrailingSlash,
      handleMethodNotAllowed: handleMethodNotAllowed,
      defaultOptionsEnabled: defaultOptionsEnabled,
      etagStrategy: etagStrategy,
    );
  }

  final bool redirectTrailingSlash;
  final bool handleMethodNotAllowed;
  final bool defaultOptionsEnabled;
  final EtagStrategy etagStrategy;

  static EtagStrategy parseEtagStrategy(
    Object? value, {
    required String context,
  }) {
    if (value is EtagStrategy) {
      return value;
    }
    final token = parseStringLike(
      value,
      context: context,
      allowEmpty: true,
      throwOnInvalid: true,
    );
    if (token == null || token.isEmpty) {
      return EtagStrategy.disabled;
    }
    switch (token.toLowerCase()) {
      case 'disabled':
      case 'none':
        return EtagStrategy.disabled;
      case 'weak':
        return EtagStrategy.weak;
      case 'strong':
        return EtagStrategy.strong;
      default:
        throw ProviderConfigException(
          '$context must be "disabled", "strong", or "weak".',
        );
    }
  }

  static String etagToString(EtagStrategy strategy) {
    switch (strategy) {
      case EtagStrategy.disabled:
        return 'disabled';
      case EtagStrategy.weak:
        return 'weak';
      case EtagStrategy.strong:
        return 'strong';
    }
  }
}

class RoutingConfigContext extends ConfigSpecContext {
  const RoutingConfigContext({
    required this.engineConfig,
    super.config,
  });

  final EngineConfig engineConfig;
}

class RoutingConfigSpec extends ConfigSpec<RoutingConfig> {
  const RoutingConfigSpec();

  @override
  String get root => 'routing';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Routing Configuration',
        description: 'Core routing behavior configuration.',
        properties: {
          'redirect_trailing_slash': ConfigSchema.boolean(
        description: 'Automatically redirect /path/ to /path.',
        defaultValue: true,
      ),
          'handle_method_not_allowed': ConfigSchema.boolean(
            description: 'Return 405 responses when a route exists but the method does not.',
        defaultValue: true,
      ),
          'default_options': ConfigSchema.boolean(
            description: 'Serve automatic OPTIONS responses enumerating allowed methods when no handler is defined.',
        defaultValue: true,
      ),
          'etag': ConfigSchema.object(
            description: 'ETag generation settings.',
            properties: {
              'strategy': ConfigSchema.string(
                description: 'Default ETag strategy (disabled, strong, weak).',
                defaultValue: 'disabled',
              ),
            },
          ),
        },
      );

  @override
  RoutingConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return RoutingConfig.fromMap(map);
  }

  @override
  Map<String, dynamic> toMap(RoutingConfig value) {
    return {
      'redirect_trailing_slash': value.redirectTrailingSlash,
      'handle_method_not_allowed': value.handleMethodNotAllowed,
      'default_options': value.defaultOptionsEnabled,
      'etag': {'strategy': RoutingConfig.etagToString(value.etagStrategy)},
    };
  }
}
