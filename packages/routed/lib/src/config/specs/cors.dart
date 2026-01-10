import 'package:collection/collection.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/utils/deep_merge.dart';

import '../spec.dart';

const List<String> _defaultAllowedOrigins = ['*'];
const List<String> _defaultAllowedMethods = [
  'GET',
  'POST',
  'PUT',
  'DELETE',
  'PATCH',
  'OPTIONS',
];
const List<String> _defaultAllowedHeaders = <String>[];
const List<String> _defaultExposedHeaders = <String>[];

class CorsConfigSpec extends ConfigSpec<CorsConfig> {
  const CorsConfigSpec();

  static const CorsConfig _defaultCors = CorsConfig();
  static const ListEquality<String> _listEquality = ListEquality<String>();

  @override
  String get root => 'cors';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) => const {};

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'CORS Configuration',
    description: 'Configuration for Cross-Origin Resource Sharing (CORS).',
    properties: {
      'enabled': ConfigSchema.boolean(
        description: 'Enables CORS middleware.',
        defaultValue: _defaultCors.enabled,
      ),
      'allowed_origins': ConfigSchema.list(
        description: 'Origins allowed to access this application.',
        items: ConfigSchema.string(),
        defaultValue: _defaultAllowedOrigins,
      ),
      'allowed_methods': ConfigSchema.list(
        description: 'HTTP methods permitted for CORS requests.',
        items: ConfigSchema.string(),
        defaultValue: _defaultAllowedMethods,
      ),
      'allowed_headers': ConfigSchema.list(
        description: 'Request headers accepted for CORS requests.',
        items: ConfigSchema.string(),
        defaultValue: _defaultAllowedHeaders,
      ),
      'exposed_headers': ConfigSchema.list(
        description: 'Response headers exposed to the browser.',
        items: ConfigSchema.string(),
        defaultValue: _defaultExposedHeaders,
      ),
      'allow_credentials': ConfigSchema.boolean(
        description: 'Whether cookies/credentials can be shared cross-origin.',
        defaultValue: _defaultCors.allowCredentials,
      ),
      'max_age': ConfigSchema.integer(
        description: 'Preflight cache duration in seconds.',
        defaultValue: _defaultCors.maxAge,
      ),
    },
  );

  CorsConfig resolveFromConfig(Config config, {CorsConfig? existing}) {
    final overrides = _mergeOverrides(config);
    if (existing != null && overrides.isEmpty) {
      return existing;
    }
    if (existing != null &&
        overrides.isNotEmpty &&
        _matchesDefault(overrides)) {
      return existing;
    }
    final context = ConfigSpecContext(config: config);
    final base = existing != null
        ? toMap(existing)
        : defaults(context: context);
    final merged = <String, dynamic>{};
    deepMerge(merged, base, override: true);
    if (overrides.isNotEmpty) {
      deepMerge(merged, overrides, override: true);
    }
    return fromMap(merged, context: context);
  }

  Map<String, dynamic> _mergeOverrides(Config config) {
    final merged = <String, dynamic>{};
    final securityNode = config.get<Object?>('security.cors');
    if (securityNode != null) {
      deepMerge(
        merged,
        _corsNodeToMap(securityNode, 'security.cors'),
        override: true,
      );
    }
    final corsNode = config.get<Object?>('cors');
    if (corsNode != null) {
      deepMerge(merged, _corsNodeToMap(corsNode, 'cors'), override: true);
    }
    return merged;
  }

  Map<String, dynamic> _corsNodeToMap(Object value, String context) {
    if (value is CorsConfig) {
      return toMap(value);
    }
    return stringKeyedMap(value, context);
  }

  bool _matchesDefault(Map<String, dynamic> overrides) {
    for (final entry in overrides.entries) {
      final key = entry.key;
      final value = entry.value;
      switch (key) {
        case 'enabled':
          if (value is! bool || value != _defaultCors.enabled) {
            return false;
          }
          break;
        case 'allow_credentials':
          if (value is! bool || value != _defaultCors.allowCredentials) {
            return false;
          }
          break;
        case 'allowed_origins':
          final parsed =
              parseStringList(
                value,
                context: 'cors.allowed_origins',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[];
          if (!_listEquality.equals(parsed, _defaultCors.allowedOrigins)) {
            return false;
          }
          break;
        case 'allowed_methods':
          final parsed =
              parseStringList(
                value,
                context: 'cors.allowed_methods',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[];
          if (!_listEquality.equals(parsed, _defaultCors.allowedMethods)) {
            return false;
          }
          break;
        case 'allowed_headers':
          final parsed =
              parseStringList(
                value,
                context: 'cors.allowed_headers',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[];
          if (!_listEquality.equals(parsed, _defaultCors.allowedHeaders)) {
            return false;
          }
          break;
        case 'exposed_headers':
          final parsed =
              parseStringList(
                value,
                context: 'cors.exposed_headers',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[];
          if (!_listEquality.equals(parsed, _defaultCors.exposedHeaders)) {
            return false;
          }
          break;
        case 'max_age':
          if (value == null) {
            if (_defaultCors.maxAge != null) return false;
            break;
          }
          if (value is! int || value != _defaultCors.maxAge) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
    return true;
  }

  @override
  CorsConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'cors.enabled',
          throwOnInvalid: true,
        ) ??
        _defaultCors.enabled;

    final allowedOriginsValue = map['allowed_origins'];
    final allowedOrigins = allowedOriginsValue == null
        ? _defaultCors.allowedOrigins
        : (parseStringList(
                allowedOriginsValue,
                context: 'cors.allowed_origins',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[]);

    final allowedMethodsValue = map['allowed_methods'];
    final allowedMethods = allowedMethodsValue == null
        ? _defaultCors.allowedMethods
        : (parseStringList(
                allowedMethodsValue,
                context: 'cors.allowed_methods',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[]);

    final allowedHeadersValue = map['allowed_headers'];
    final allowedHeaders = allowedHeadersValue == null
        ? _defaultCors.allowedHeaders
        : (parseStringList(
                allowedHeadersValue,
                context: 'cors.allowed_headers',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[]);

    final allowCredentials =
        parseBoolLike(
          map['allow_credentials'],
          context: 'cors.allow_credentials',
          throwOnInvalid: true,
        ) ??
        _defaultCors.allowCredentials;

    final maxAgeValue = map['max_age'];
    final int? maxAge;
    if (maxAgeValue == null) {
      maxAge = _defaultCors.maxAge;
    } else {
      maxAge = parseIntLike(
        maxAgeValue,
        context: 'cors.max_age',
        allowEmpty: false,
        throwOnInvalid: true,
      );
    }

    final exposedHeadersValue = map['exposed_headers'];
    final exposedHeaders = exposedHeadersValue == null
        ? _defaultCors.exposedHeaders
        : (parseStringList(
                exposedHeadersValue,
                context: 'cors.exposed_headers',
                allowEmptyResult: true,
                allowCommaSeparated: false,
                throwOnInvalid: true,
              ) ??
              const <String>[]);

    return CorsConfig(
      enabled: enabled,
      allowedOrigins: List<String>.from(allowedOrigins),
      allowedMethods: List<String>.from(allowedMethods),
      allowedHeaders: List<String>.from(allowedHeaders),
      allowCredentials: allowCredentials,
      maxAge: maxAge,
      exposedHeaders: List<String>.from(exposedHeaders),
    );
  }

  @override
  Map<String, dynamic> toMap(CorsConfig value) {
    return {
      'enabled': value.enabled,
      'allowed_origins': List<String>.from(value.allowedOrigins),
      'allowed_methods': List<String>.from(value.allowedMethods),
      'allowed_headers': List<String>.from(value.allowedHeaders),
      'allow_credentials': value.allowCredentials,
      'max_age': value.maxAge,
      'exposed_headers': List<String>.from(value.exposedHeaders),
    };
  }
}
