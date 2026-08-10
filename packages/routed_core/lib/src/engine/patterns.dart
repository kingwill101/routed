part of 'engine.dart';

class TypeDefinition {
  final String name;
  final String pattern;
  final dynamic Function(String?) cast;

  TypeDefinition(this.name, this.pattern, [dynamic Function(String?)? cast])
    : cast = cast ?? ((String? value) => value);
}

RoutePatternRegistry requireRoutePatternRegistry(Container container) {
  if (!container.has<RoutePatternRegistry>()) {
    throw StateError(
      'RoutePatternRegistry is not registered. '
      'Register RoutingServiceProvider to use routing features.',
    );
  }
  return container.get<RoutePatternRegistry>();
}

class RouteTypeRegistry extends NamedRegistry<TypeDefinition> {
  RouteTypeRegistry();

  RouteTypeRegistry.defaults() {
    _registerDefaults();
  }

  RouteTypeRegistry.clone(RouteTypeRegistry source) {
    for (final name in source.entryNames) {
      final definition = source.getEntry(name);
      if (definition != null) {
        registerEntry(name, definition);
      }
    }
  }

  void register(
    String name,
    String pattern, {
    dynamic Function(String?)? cast,
  }) {
    final key = normalizeName(name);
    registerEntry(key, TypeDefinition(key, pattern, cast));
  }

  TypeDefinition? resolve(String name) => getEntry(name);

  String? patternFor(String name) => getEntry(name)?.pattern;

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
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    register('slug', r'[a-z0-9]+(?:-[a-z0-9]+)*');
    register('word', r'\w+');
    register('string', r'[^/]+');
    register('date', r'\d{4}-\d{2}-\d{2}');
    register('email', r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    register('url', r'https?://[^\s/$.?#].[^\s]*');
    register('ip', r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
  }
}

class RouteParamPatternRegistry extends NamedRegistry<String> {
  RouteParamPatternRegistry();

  RouteParamPatternRegistry.clone(RouteParamPatternRegistry source) {
    for (final name in source.entryNames) {
      final pattern = source.getEntry(name);
      if (pattern != null) {
        registerEntry(name, pattern);
      }
    }
  }

  void register(String name, String pattern) {
    registerEntry(name, pattern);
  }

  String? resolve(String name) => getEntry(name);

  Iterable<String> get names => entryNames;
}

class RoutePatternRegistry {
  RoutePatternRegistry({
    RouteTypeRegistry? types,
    RouteParamPatternRegistry? params,
  }) : types = types ?? RouteTypeRegistry.defaults(),
       params = params ?? RouteParamPatternRegistry();

  RoutePatternRegistry.defaults()
    : types = RouteTypeRegistry.defaults(),
      params = RouteParamPatternRegistry();

  RoutePatternRegistry.clone(RoutePatternRegistry source)
    : types = RouteTypeRegistry.clone(source.types),
      params = RouteParamPatternRegistry.clone(source.params);

  final RouteTypeRegistry types;
  final RouteParamPatternRegistry params;

  void registerType(
    String name,
    String pattern, {
    dynamic Function(String?)? cast,
  }) {
    types.register(name, pattern, cast: cast);
  }

  void registerParamPattern(String name, String pattern) {
    params.register(name, pattern);
  }

  TypeDefinition? resolveType(String name) => types.resolve(name);

  String? resolveTypePattern(String name) => types.patternFor(name);

  String? resolveParamPattern(String name) => params.resolve(name);

  dynamic cast(String? value, String type) {
    if (value == null) return null;
    final definition = resolveType(type);
    if (definition != null) {
      return definition.cast(value);
    }
    return value;
  }
}
