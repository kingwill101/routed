import 'dart:async';

import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/utils/deep_copy.dart';

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

  /// Resolves the available options, preferring dynamic builders.
  List<String>? resolveOptions() {
    if (optionsBuilder != null) {
      final resolved = optionsBuilder!();
      return resolved.isEmpty ? null : List<String>.from(resolved);
    }
    if (options == null || options!.isEmpty) return null;
    return List<String>.from(options!);
  }
}

/// Combined defaults and documentation returned by [ProvidesDefaultConfig].
class ConfigDefaults {
  const ConfigDefaults({
    Map<String, dynamic> values = const {},
    List<ConfigDocEntry> docs = const <ConfigDocEntry>[],
  }) : _values = values,
       _docs = docs;

  final Map<String, dynamic> _values;
  final List<ConfigDocEntry> _docs;

  /// Default configuration values keyed by dotted path.
  Map<String, dynamic> get values {
    if (_values.isEmpty) {
      return _buildValuesFromDocs(_docs);
    }
    final merged = deepCopyMap(_values);
    if (_docs.isEmpty) {
      return merged;
    }
    for (final doc in _docs) {
      final defaultValue = doc.defaultValue;
      if (defaultValue == null) continue;
      if (_lookupByPath(merged, doc.path) != null) continue;
      _assignByPath(merged, doc.path, deepCopyValue(defaultValue));
    }
    return merged;
  }

  /// Documentation entries describing configuration fields.
  List<ConfigDocEntry> get docs => _mergeDefaultValues(values, _docs);

  static Map<String, dynamic> _buildValuesFromDocs(List<ConfigDocEntry> docs) {
    final result = <String, dynamic>{};
    for (final entry in docs) {
      if (entry.defaultValue == null) continue;
      _assignByPath(result, entry.path, deepCopyValue(entry.defaultValue));
    }
    return result;
  }

  static List<ConfigDocEntry> _mergeDefaultValues(
    Map<String, dynamic> values,
    List<ConfigDocEntry> docs,
  ) {
    return docs
        .map(
          (entry) => entry.defaultValue != null
              ? entry
              : ConfigDocEntry(
                  path: entry.path,
                  type: entry.type,
                  description: entry.description,
                  example: entry.example,
                  deprecated: entry.deprecated,
                  options: entry.options,
                  optionsBuilder: entry.optionsBuilder,
                  metadata: entry.metadata,
                  defaultValue: _lookupByPath(values, entry.path),
                ),
        )
        .toList(growable: false);
  }

  static Object? _lookupByPath(Map<String, dynamic> map, String path) {
    final segments = path.split('.');
    dynamic current = map;
    for (final segment in segments) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  static void _assignByPath(
    Map<String, dynamic> target,
    String path,
    Object? value,
  ) {
    final segments = path.split('.');
    Map<String, dynamic> current = target;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      if (isLast) {
        current[segment] = value;
      } else {
        final next = current[segment];
        if (next is Map<String, dynamic>) {
          current = next;
        } else if (next == null) {
          final newMap = <String, dynamic>{};
          current[segment] = newMap;
          current = newMap;
        } else {
          // Overwrite non-map entry to maintain consistency.
          final newMap = <String, dynamic>{};
          current[segment] = newMap;
          current = newMap;
        }
      }
    }
  }
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
