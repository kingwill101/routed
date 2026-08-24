part of 'engine.dart';

/// Defines a named route parameter type and its conversion behavior.
class TypeDefinition {
  /// Creates a type definition for [name] and [pattern].
  TypeDefinition(this.name, this.pattern, [dynamic Function(String?)? cast])
    : cast = cast ?? ((String? value) => value);

  /// The type name used in route patterns.
  final String name;

  /// The regular expression used to match values of this type.
  final String pattern;

  /// Converts a matched value to the type's runtime representation.
  final dynamic Function(String?) cast;
}

/// Returns the route pattern registry from [container].
RoutePatternRegistry requireRoutePatternRegistry(Container container) {
  if (!container.has<RoutePatternRegistry>()) {
    throw StateError(
      'RoutePatternRegistry is not registered. '
      'Register RoutingServiceProvider to use routing features.',
    );
  }
  return container.get<RoutePatternRegistry>();
}

/// Registry of named route parameter type definitions.
class RouteTypeRegistry extends NamedRegistry<TypeDefinition> {
  /// Creates an empty type registry.
  RouteTypeRegistry();

  /// Creates a registry containing the built-in route types.
  RouteTypeRegistry.defaults() {
    _registerDefaults();
  }

  /// Creates a copy of [source].
  RouteTypeRegistry.clone(RouteTypeRegistry source) {
    for (final name in source.entryNames) {
      final definition = source.getEntry(name);
      if (definition != null) {
        registerEntry(name, definition);
      }
    }
  }

  /// Registers a named route type.
  void register(
    String name,
    String pattern, {
    dynamic Function(String?)? cast,
  }) {
    final key = normalizeName(name);
    registerEntry(key, TypeDefinition(key, pattern, cast));
  }

  /// Resolves the definition named [name].
  TypeDefinition? resolve(String name) => getEntry(name);

  /// Returns the matching expression for [name].
  String? patternFor(String name) => getEntry(name)?.pattern;

  /// The names registered in this registry.
  Iterable<String> get names => entryNames;

  void _registerDefaults() {
    register('int', r'\d+', cast: (String? value) => int.tryParse(value ?? ''));
    register(
      'double',
      r'\d+(\.\d+)?',
      cast: (String? value) => double.tryParse(value ?? ''),
    );
    register(
      'uuid',
      '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    register('slug', '[a-z0-9]+(?:-[a-z0-9]+)*');
    register('word', r'\w+');
    register('string', '[^/]+');
    register('date', r'\d{4}-\d{2}-\d{2}');
    register('email', r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    register('url', r'https?://[^\s/$.?#].[^\s]*');
    register('ip', r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
  }
}

/// Registry of expressions applied to named route parameters.
class RouteParamPatternRegistry extends NamedRegistry<String> {
  /// Creates an empty parameter-pattern registry.
  RouteParamPatternRegistry();

  /// Creates a copy of [source].
  RouteParamPatternRegistry.clone(RouteParamPatternRegistry source) {
    for (final name in source.entryNames) {
      final pattern = source.getEntry(name);
      if (pattern != null) {
        registerEntry(name, pattern);
      }
    }
  }

  /// Registers a pattern under [name].
  void register(String name, String pattern) {
    registerEntry(name, pattern);
  }

  /// Resolves the pattern named [name].
  String? resolve(String name) => getEntry(name);

  /// The names registered in this registry.
  Iterable<String> get names => entryNames;
}

/// Groups route type and parameter-pattern registries.
class RoutePatternRegistry {
  /// Creates a registry from optional type and parameter registries.
  RoutePatternRegistry({
    RouteTypeRegistry? types,
    RouteParamPatternRegistry? params,
  }) : types = types ?? RouteTypeRegistry.defaults(),
       params = params ?? RouteParamPatternRegistry();

  /// Creates a registry with the built-in route types.
  RoutePatternRegistry.defaults()
    : types = RouteTypeRegistry.defaults(),
      params = RouteParamPatternRegistry();

  /// Creates a deep copy of [source].
  RoutePatternRegistry.clone(RoutePatternRegistry source)
    : types = RouteTypeRegistry.clone(source.types),
      params = RouteParamPatternRegistry.clone(source.params);

  /// Named type definitions used by route patterns.
  final RouteTypeRegistry types;

  /// Named parameter expressions used by route patterns.
  final RouteParamPatternRegistry params;

  /// Registers a named route type.
  void registerType(
    String name,
    String pattern, {
    dynamic Function(String?)? cast,
  }) {
    types.register(name, pattern, cast: cast);
  }

  /// Registers a pattern for the parameter named [name].
  void registerParamPattern(String name, String pattern) {
    params.register(name, pattern);
  }

  /// Resolves a named route type.
  TypeDefinition? resolveType(String name) => types.resolve(name);

  /// Returns the expression for a named route type.
  String? resolveTypePattern(String name) => types.patternFor(name);

  /// Returns the expression for a named route parameter.
  String? resolveParamPattern(String name) => params.resolve(name);

  /// Converts [value] using the named route [type].
  dynamic cast(String? value, String type) {
    if (value == null) return null;
    final definition = resolveType(type);
    if (definition != null) {
      return definition.cast(value);
    }
    return value;
  }
}
