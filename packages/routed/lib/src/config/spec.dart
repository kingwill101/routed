import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/utils/deep_merge.dart';

/// Context passed to config specs for computing defaults or parsing values.
class ConfigSpecContext {
  const ConfigSpecContext({this.config});

  /// The full application configuration, if available.
  final Config? config;
}

/// Typed configuration specification for a config namespace.
///
/// Specs provide defaults, documentation, and a typed model that can be
/// resolved from user-supplied configuration maps.
abstract class ConfigSpec<T> {
  const ConfigSpec();

  /// Top-level config namespace (e.g. `cache`, `session`, `storage`).
  String get root;

  /// Default values expressed as a map rooted at [root].
  Map<String, dynamic> defaults({ConfigSpecContext? context});

  /// Default values wrapped in the top-level [root] key.
  Map<String, dynamic> defaultsWithRoot({ConfigSpecContext? context}) {
    final inner = defaults(context: context);
    if (inner.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{root: inner};
  }

  /// Documentation entries for the spec, rooted at [pathBase] or [root].
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context});

  /// The JSON Schema for this configuration.
  ///
  /// If provided, this schema can be used for validation and documentation generation.
  Schema? get schema => null;

  /// Parse a typed model from a config map scoped to the spec's root.
  T fromMap(Map<String, dynamic> map, {ConfigSpecContext? context});

  /// Convert a typed model into a config map scoped to the spec's root.
  Map<String, dynamic> toMap(T value);

  /// Merge defaults with user-provided config, with user values winning.
  Map<String, dynamic> mergeDefaults(
    Map<String, dynamic> user, {
    ConfigSpecContext? context,
  }) {
    final merged = <String, dynamic>{};
    final defaultValues = defaults(context: context);
    if (defaultValues.isNotEmpty) {
      deepMerge(merged, defaultValues, override: true);
    }
    if (user.isNotEmpty) {
      deepMerge(merged, user, override: true);
    }
    return merged;
  }

  /// Resolve a typed model from the current [config].
  T resolve(Config config, {ConfigSpecContext? context}) {
    final resolvedContext = context ?? ConfigSpecContext(config: config);
    final rawValue = config.get<Object?>(root);
    final raw =
        rawValue == null ? const <String, dynamic>{} : _stringKeyedMap(rawValue, root);
    final merged = mergeDefaults(raw, context: resolvedContext);
    return fromMap(merged, context: resolvedContext);
  }
}

Map<String, dynamic> _stringKeyedMap(Object value, String context) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    final copy = <String, dynamic>{};
    value.forEach((key, entry) {
      copy[key.toString()] = entry;
    });
    return copy;
  }
  throw ProviderConfigException('$context must be a map');
}
