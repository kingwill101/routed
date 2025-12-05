import 'package:routed/src/contracts/contracts.dart' show Config;

/// Describes middleware contributions from a service provider.
///
/// A provider can contribute middleware globally or to specific named groups.
/// This allows providers to register middleware that will be automatically
/// applied to routes based on configuration.
///
/// Example:
/// ```dart
/// final contribution = ProviderMiddlewareContribution(
///   global: ['logging', 'compression'],
///   groups: {
///     'auth': ['session', 'csrf'],
///     'api': ['rate-limit'],
///   },
/// );
/// ```
class ProviderMiddlewareContribution {
  /// Creates a new middleware contribution.
  ///
  /// The [global] list contains middleware identifiers that should be applied
  /// to all routes. The [groups] map contains named middleware groups, where
  /// each key is a group name and the value is a list of middleware identifiers.
  ProviderMiddlewareContribution({
    this.global = const <String>[],
    this.groups = const <String, List<String>>{},
  });

  /// Middleware identifiers to be applied globally to all routes.
  final List<String> global;

  /// Named middleware groups with their associated middleware identifiers.
  ///
  /// Each key is a group name, and the value is a list of middleware identifiers
  /// that belong to that group.
  final Map<String, List<String>> groups;

  /// Creates a copy of this contribution with updated values.
  ///
  /// Any parameters not provided will retain their current values.
  ProviderMiddlewareContribution copyWith({
    List<String>? global,
    Map<String, List<String>>? groups,
  }) {
    return ProviderMiddlewareContribution(
      global: global ?? this.global,
      groups: groups ?? this.groups,
    );
  }
}

/// Manifest describing providers and their middleware contributions.
///
/// This class loads provider and middleware configuration from the application
/// configuration, typically from a YAML or JSON config file. It describes which
/// service providers should be registered and what middleware each provider
/// contributes.
///
/// Example configuration:
/// ```yaml
/// http:
///   providers:
///     - 'App\Providers\AuthServiceProvider'
///     - 'App\Providers\LoggingServiceProvider'
///   middleware_sources:
///     AuthServiceProvider:
///       global: ['session']
///       groups:
///         auth: ['authenticate', 'authorize']
/// ```
class ProviderManifest {
  /// Creates a new provider manifest.
  ///
  /// The [providers] list contains the class names or identifiers of service
  /// providers to register. The [middlewareSources] map describes which
  /// providers contribute middleware and what they contribute.
  ProviderManifest({required this.providers, required this.middlewareSources});

  /// List of service provider identifiers to be registered.
  final List<String> providers;

  /// Maps provider identifiers to their middleware contributions.
  ///
  /// Each key is a provider identifier, and the value describes what middleware
  /// that provider contributes globally or to specific groups.
  final Map<String, ProviderMiddlewareContribution> middlewareSources;

  /// Creates a provider manifest from application configuration.
  ///
  /// Reads the `http.providers` and `http.middleware_sources` configuration
  /// keys to build the manifest. If these keys are not present, empty
  /// defaults are used.
  ///
  /// Example:
  /// ```dart
  /// final manifest = ProviderManifest.fromConfig(config);
  /// print('Providers: ${manifest.providers}');
  /// ```
  factory ProviderManifest.fromConfig(Config config) {
    final rawProviders = config.get('http.providers') ?? const <String>[];
    final providers = rawProviders is List<String>
        ? rawProviders
        : List<String>.from(rawProviders as List);
    final sources = <String, ProviderMiddlewareContribution>{};
    final rawSources = config.get(
      'http.middleware_sources',
      const <String, dynamic>{},
    );
    if (rawSources is Map) {
      rawSources?.forEach((key, value) {
        if (key is! String || value is! Map) return;
        sources[key] = ProviderMiddlewareContribution(
          global: _stringList(value['global']),
          groups: _groupMap(value['groups']),
        );
      });
    }

    return ProviderManifest(providers: providers, middlewareSources: sources);
  }

  /// Converts a dynamic value to a list of strings.
  ///
  /// Returns an empty list if [value] is not a list.
  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  /// Converts a dynamic value to a map of string keys to string lists.
  ///
  /// This is used to parse middleware group configurations where each group
  /// name maps to a list of middleware identifiers. Returns an empty map if
  /// [value] is not a map or has an invalid structure.
  static Map<String, List<String>> _groupMap(Object? value) {
    if (value is Map) {
      final result = <String, List<String>>{};
      value.forEach((key, group) {
        if (group is Iterable && key is String) {
          result[key] = group.map((e) => e.toString()).toList();
        }
      });
      return result;
    }
    return const <String, List<String>>{};
  }
}
