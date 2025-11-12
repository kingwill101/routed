/// Registry for locale resolver factories referenceable from configuration.
library;

import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/support/named_registry.dart';
import 'package:routed/src/translation/resolvers.dart';

/// Provides shared options derived from core translation config.
class LocaleResolverSharedOptions {
  LocaleResolverSharedOptions({
    required this.queryParameter,
    required this.cookieName,
    required this.sessionKey,
    required this.headerName,
  });

  /// Query parameter inspected by the default query resolver.
  final String queryParameter;

  /// Cookie name inspected by the default cookie resolver.
  final String cookieName;

  /// Session key inspected by the session resolver.
  final String sessionKey;

  /// Header inspected by the header resolver.
  final String headerName;
}

/// Context passed to resolver factories when constructing instances.
class LocaleResolverBuildContext {
  LocaleResolverBuildContext({
    required this.id,
    required this.sharedOptions,
    required Map<String, dynamic> options,
    this.config,
  }) : _options = Map<String, dynamic>.from(options);

  /// Resolver identifier from `translation.resolvers`.
  final String id;

  /// Shared options computed from the main translation config.
  final LocaleResolverSharedOptions sharedOptions;

  /// Raw resolver-specific options pulled from `translation.resolver_options`.
  final Map<String, dynamic> _options;

  /// Application configuration snapshot.
  final Config? config;

  /// Returns an option value cast to the requested type.
  T? option<T>(String key) => _options[key] as T?;

  /// Exposes all resolver options.
  Map<String, dynamic> get options => Map.unmodifiable(_options);
}

/// Function signature used when registering locale resolver builders.
typedef LocaleResolverFactory =
    LocaleResolver Function(LocaleResolverBuildContext context);

/// Named registry storing resolver factories addressable by slug.
class LocaleResolverRegistry extends NamedRegistry<LocaleResolverFactory> {
  LocaleResolverRegistry();

  LocaleResolverRegistry.clone(LocaleResolverRegistry source) {
    for (final name in source.entryNames) {
      final factory = source.getEntry(name);
      if (factory != null) {
        registerEntry(name, factory);
      }
    }
  }

  /// Registers a resolver factory under [id].
  void register(String id, LocaleResolverFactory factory) {
    registerEntry(id, factory);
  }

  /// Looks up the resolver factory registered for [id].
  LocaleResolverFactory? resolve(String id) => getEntry(id);

  /// Whether a resolver has already been registered.
  bool contains(String id) => containsEntry(id);

  /// Returns all resolver identifiers.
  Iterable<String> get identifiers => entryNames;
}
