import 'dart:async';

import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/utils/deep_copy.dart';
import 'package:routed/src/utils/dot.dart';

typedef ConfigDocOptionsBuilder = List<String> Function();

/// Metadata key used to indicate an environment variable override.
const String configDocMetaInheritFromEnv = 'inheritFromEnv';

/// Describes a configuration entry contributed by a [ProvidesDefaultConfig] provider.
class ConfigDocEntry {
  const ConfigDocEntry({
    required this.path,
    this.type,
    this.description,
    this.example,
    this.deprecated = false,
    this.options,
    this.optionsBuilder,
    this.metadata = const <String, Object?>{},
    this.defaultValue,
    this.defaultValueBuilder,
  });

  /// Dot-delimited configuration path (e.g. `cache.default`).
  final String path;

  /// Optional machine-readable type hint (`string`, `int`, `bool`, etc.).
  final String? type;

  /// Human-friendly explanation of what this value controls.
  final String? description;

  /// Example value rendered in documentation.
  final String? example;

  /// Whether the value is considered deprecated.
  final bool deprecated;

  /// Static list of supported options, if known.
  final List<String>? options;

  /// Lazy options generator for dynamic registries.
  final ConfigDocOptionsBuilder? optionsBuilder;

  /// Additional metadata the consumer may find useful.
  final Map<String, Object?> metadata;

  /// Default value contributed by the provider (if any).
  final Object? defaultValue;

  /// Lazily computed default value, evaluated when defaults are materialised.
  final Object? Function()? defaultValueBuilder;

  /// Resolves the available options, preferring dynamic builders.
  List<String>? resolveOptions() {
    if (optionsBuilder != null) {
      final resolved = optionsBuilder!();
      return resolved.isEmpty ? null : List<String>.from(resolved);
    }
    if (options == null || options!.isEmpty) return null;
    return List<String>.from(options!);
  }

  /// Resolves the default value, evaluating the builder when provided.
  Object? resolveDefaultValue() {
    if (defaultValue != null) {
      return defaultValue;
    }
    if (defaultValueBuilder != null) {
      return defaultValueBuilder!();
    }
    return null;
  }

  bool get hasExplicitDefault =>
      defaultValue != null || defaultValueBuilder != null;
}

/// Combined defaults and documentation returned by [ProvidesDefaultConfig].
class ConfigDefaults {
  const ConfigDefaults({
    List<ConfigDocEntry> docs = const <ConfigDocEntry>[],
    Map<String, dynamic>? values,
    Map<String, Schema> schemas = const {},
  }) : _docs = docs,
       _values = values,
       _schemas = schemas;

  final List<ConfigDocEntry> _docs;
  final Map<String, dynamic>? _values;
  final Map<String, Schema> _schemas;

  /// The JSON Schemas for this configuration, keyed by root path.
  Map<String, Schema> get schemas => Map.unmodifiable(_schemas);

  /// Default configuration values keyed by dotted path.
  Map<String, dynamic> get values {
    if (_values != null) {
      return deepCopyMap(_values);
    }

    if (_schemas.isNotEmpty) {
      final result = <String, dynamic>{};
      for (final entry in _schemas.entries) {
        result[entry.key] = ConfigSchema.extractDefaults(entry.value);
      }
      return result;
    }

    return _computeDefaults(_docs).values;
  }

  /// Documentation entries describing configuration fields.
  List<ConfigDocEntry> get docs {
    var effectiveDocs = _docs;
    if (effectiveDocs.isEmpty && _schemas.isNotEmpty) {
      effectiveDocs = [];
      for (final entry in _schemas.entries) {
        effectiveDocs.addAll(
          ConfigSchema.toDocEntries(entry.value, pathBase: entry.key),
        );
      }
    }

    final computed = _computeDefaults(effectiveDocs);
    final values = _values;
    final resolvedValues = values != null
        ? deepCopyMap(values)
        : computed.values;
    return _mergeDefaultValues(
      resolvedValues,
      computed.docDefaults,
      effectiveDocs,
    );
  }

  /// Produces a snapshot containing both values and documentation in one pass.
  ConfigDefaultsSnapshot snapshot() {
    var effectiveDocs = _docs;
    if (effectiveDocs.isEmpty && _schemas.isNotEmpty) {
      effectiveDocs = [];
      for (final entry in _schemas.entries) {
        effectiveDocs.addAll(
          ConfigSchema.toDocEntries(entry.value, pathBase: entry.key),
        );
      }
    }

    final computed = _computeDefaults(effectiveDocs);

    Map<String, dynamic> resolvedValues;
    if (_values != null) {
      resolvedValues = deepCopyMap(_values);
    } else if (_schemas.isNotEmpty) {
      resolvedValues = <String, dynamic>{};
      for (final entry in _schemas.entries) {
        resolvedValues[entry.key] = ConfigSchema.extractDefaults(entry.value);
      }
    } else {
      resolvedValues = computed.values;
    }

    final mergedDocs = _mergeDefaultValues(
      resolvedValues,
      computed.docDefaults,
      effectiveDocs,
    );

    return ConfigDefaultsSnapshot(
      values: resolvedValues,
      docs: mergedDocs,
      schemas: schemas,
    );
  }

  static _ComputedDefaults _computeDefaults(List<ConfigDocEntry> docs) {
    final result = <String, dynamic>{};
    final providedDefaults = <String, Object?>{};
    for (final entry in docs) {
      if (entry.path.contains('*')) {
        continue;
      }
      final resolved = entry.resolveDefaultValue();
      if (resolved == null) continue;
      dot.set(result, entry.path, deepCopyValue(resolved));
      providedDefaults[entry.path] = deepCopyValue(dot.get(result, entry.path));
    }
    return _ComputedDefaults(result, providedDefaults);
  }

  static List<ConfigDocEntry> _mergeDefaultValues(
    Map<String, dynamic> values,
    Map<String, Object?> docDefaults,
    List<ConfigDocEntry> docs,
  ) {
    return docs
        .map((entry) {
          final provided = docDefaults.containsKey(entry.path);
          final resolvedDefault = provided
              ? docDefaults[entry.path]
              : dot.get(values, entry.path);
          return ConfigDocEntry(
            path: entry.path,
            type: entry.type,
            description: entry.description,
            example: entry.example,
            deprecated: entry.deprecated,
            options: entry.options,
            optionsBuilder: entry.optionsBuilder,
            metadata: entry.metadata,
            defaultValue: resolvedDefault,
            defaultValueBuilder: entry.defaultValueBuilder,
          );
        })
        .toList(growable: false);
  }
}

class _ComputedDefaults {
  _ComputedDefaults(this.values, this.docDefaults);

  final Map<String, dynamic> values;
  final Map<String, Object?> docDefaults;
}

class ConfigDefaultsSnapshot {
  ConfigDefaultsSnapshot({
    required this.values,
    required this.docs,
    this.schemas = const {},
  });

  final Map<String, dynamic> values;
  final List<ConfigDocEntry> docs;
  final Map<String, Schema> schemas;
}

/// Base class for service providers that register services with the container.
///
/// Service providers are responsible for registering bindings with the container
/// and performing any necessary setup/cleanup operations. They provide a way to
/// organize related bindings and their lifecycle management.
///
/// Example:
/// ```dart
/// class MyServiceProvider extends ServiceProvider {
///   @override
///   void register(Container container) {
///     container.singleton<MyService>((c) async => MyService());
///   }
///
///   @override
///   Future<void> boot(Container container) async {
///     final service = await container.make<MyService>();
///     await service.initialize();
///   }
/// }
/// ```
abstract class ServiceProvider {
  /// Register services with the container.
  ///
  /// This method is called when the provider is registered with the container.
  /// Use this method to register bindings, instances, and aliases.
  void register(Container container);

  /// Optional boot method called after all providers are registered.
  ///
  /// This method is called after all providers have been registered,
  /// making it safe to resolve dependencies that might be registered
  /// by other providers.
  Future<void> boot(Container container) async {}

  /// Optional cleanup method called when container is disposed.
  ///
  /// Use this method to perform any necessary cleanup operations
  /// such as closing connections or freeing resources.
  Future<void> cleanup(Container container) async {}
}

/// Implement on a [ServiceProvider] to declare dependencies by type.
///
/// Providers declaring dependencies will only boot once all dependency types
/// are available in the container.
mixin ProvidesDependencies on ServiceProvider {
  /// Types that must be registered before this provider boots.
  List<Type> get dependencies => const <Type>[];
}

/// Implement on a [ServiceProvider] to advertise default configuration values.
mixin ProvidesDefaultConfig on ServiceProvider {
  /// Default configuration (values + documentation) contributed by this provider.
  ConfigDefaults get defaultConfig;

  /// The JSON Schemas for this configuration.
  Map<String, Schema> get schemas => defaultConfig.schemas;

  /// Optional identifier used when tracking config contributions.
  String get configSource => runtimeType.toString();

  /// Called when the application configuration is reloaded.
  ///
  /// Providers overriding this hook can re-apply configuration without
  /// manually subscribing to [ConfigReloadedEvent].
  Future<void> onConfigReload(Container container, Config config) async {}
}

/// Thrown when a provider encounters invalid configuration.
class ProviderConfigException implements Exception {
  ProviderConfigException(this.message);

  /// Description of the configuration error.
  final String message;

  @override
  String toString() => 'ProviderConfigException: $message';
}
