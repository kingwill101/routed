import 'dart:async';

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
  }) : _docs = docs,
       _values = values;

  final List<ConfigDocEntry> _docs;
  final Map<String, dynamic>? _values;

  /// Default configuration values keyed by dotted path.
  Map<String, dynamic> get values {
    final values = _values;
    return values != null ? deepCopyMap(values) : _computeDefaults(_docs).values;
  }

  /// Documentation entries describing configuration fields.
  List<ConfigDocEntry> get docs {
    final computed = _computeDefaults(_docs);
    final values = _values;
    final resolvedValues = values != null ? deepCopyMap(values) : computed.values;
    return _mergeDefaultValues(resolvedValues, computed.docDefaults, _docs);
  }

  /// Produces a snapshot containing both values and documentation in one pass.
  ConfigDefaultsSnapshot snapshot() {
    final computed = _computeDefaults(_docs);
    final values = _values;
    final resolvedValues = values != null ? deepCopyMap(values) : computed.values;
    final mergedDocs = _mergeDefaultValues(
      resolvedValues,
      computed.docDefaults,
      _docs,
    );
    return ConfigDefaultsSnapshot(values: resolvedValues, docs: mergedDocs);
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
  ConfigDefaultsSnapshot({required this.values, required this.docs});

  final Map<String, dynamic> values;
  final List<ConfigDocEntry> docs;
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

/// Implement on a [ServiceProvider] to advertise default configuration values.
mixin ProvidesDefaultConfig on ServiceProvider {
  /// Default configuration (values + documentation) contributed by this provider.
  ConfigDefaults get defaultConfig;

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
