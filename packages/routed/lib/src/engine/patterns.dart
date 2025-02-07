part of 'engine.dart';

class TypeDefinition {
  final String name;
  final String pattern;
  final dynamic Function(String?) cast;

  TypeDefinition(this.name, this.pattern, [dynamic Function(String?)? cast])
      : cast = cast ?? ((String? value) => value);
}

/// Custom type patterns for route parameters.
/// Maps type names to regular expression patterns.
final Map<String, TypeDefinition> _builtInTypes = {
  'int': TypeDefinition(
    'int',
    r'\d+',
    (String? value) => int.tryParse(value ?? ''),
  ),
  'double': TypeDefinition(
    'double',
    r'\d+(\.\d+)?',
    (String? value) => double.tryParse(value ?? ''),
  ),
  'uuid': TypeDefinition(
    'uuid',
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  ),
  'slug': TypeDefinition(
    'slug',
    r'[a-z0-9]+(?:-[a-z0-9]+)*',
  ),
  'word': TypeDefinition(
    'word',
    r'\w+',
  ),
  'string': TypeDefinition(
    'string',
    r'[^/]+',
  ),
  'date': TypeDefinition(
    'date',
    r'\d{4}-\d{2}-\d{2}',
  ),
  'email': TypeDefinition(
    'email',
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  ),
  'url': TypeDefinition(
    'url',
    r'https?://[^\s/$.?#].[^\s]*',
  ),
  'ip': TypeDefinition(
    'ip',
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
  ),
};

final Map<String, TypeDefinition> customTypePatterns = {
  ..._builtInTypes,
};

/// Global param patterns: if a route has {id} with NO explicit type,
/// and we've registered a pattern for 'id', we use that pattern.
final Map<String, String> _globalParamPatterns = {};

/// Register a custom type, e.g. `registerCustomType('slug', r'[a-z0-9]+(?:-[a-z0-9]+)*')`.
/// Then any route with `{foo:slug}` uses that pattern.
/// [typeName] The name of the custom type
/// [pattern] The regular expression pattern
/// [cast] An optional custom cast function
void registerCustomType(String typeName, String pattern,
    [dynamic Function(String?)? cast]) {
  customTypePatterns[typeName] = TypeDefinition(typeName, pattern, cast);
}

/// Register a global param pattern, e.g. `registerParamPattern('id', r'\d+')`.
/// Then any route placeholder `{id}` (no type) uses that pattern.
/// [paramName] The name of the parameter
/// [pattern] The regular expression pattern
void registerParamPattern(String paramName, String pattern) {
  _globalParamPatterns[paramName] = pattern;
}

/// Gets the pattern for a given type
/// [type] The type name to look up
/// Returns the pattern string or null if not found
String? getPattern(String? type) {
  return customTypePatterns[type]?.pattern;
}

/// Gets the global parameter pattern for a given parameter name
/// [paramName] The parameter name to look up
/// Returns the pattern string or null if not found
getGlobalParamPattern(String paramName) {
  return _globalParamPatterns[paramName];
}

/// Adds a custom type pattern to the patterns map
/// [name] The name of the pattern type
/// [pattern] The regular expression pattern
/// [cast] An optional custom cast function
void registerPattern(String name, String pattern,
    [dynamic Function(String?)? cast]) {
  customTypePatterns[name] = TypeDefinition(name, pattern, cast);
}

TypeDefinition? getTypeDefinition(String name) {
  return customTypePatterns[name];
}

@visibleForTesting
clearCustomPatterns() {
  customTypePatterns.clear();
  _globalParamPatterns.clear();
}
