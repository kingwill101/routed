part of 'engine.dart';

/// Custom type patterns for route parameters.
/// Maps type names to regular expression patterns.
final Map<String, String> builtInTypePatterns = {
  'int': r'\d+',
  'double': r'\d+(\.\d+)?',
  'uuid':
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  'slug': r'[a-z0-9]+(?:-[a-z0-9]+)*',
  'word': r'\w+',
  'string': r'[^/]+',
  'date': r'\d{4}-\d{2}-\d{2}',
  'email': r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  'url': r'https?://[^\s/$.?#].[^\s]*',
  'ip': r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
};
final Map<String, String> customTypePatterns = {
  ...builtInTypePatterns,
};

/// Global param patterns: if a route has {id} with NO explicit type,
/// and we've registered a pattern for 'id', we use that pattern.
final Map<String, String> _globalParamPatterns = {};

/// Register a custom type, e.g. `registerCustomType('slug', r'[a-z0-9]+(?:-[a-z0-9]+)*')`.
/// Then any route with `{foo:slug}` uses that pattern.
/// [typeName] The name of the custom type
/// [pattern] The regular expression pattern

void registerCustomType(String typeName, String pattern) {
  customTypePatterns[typeName] = pattern;
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
  return customTypePatterns[type];
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
addPattern(String name, String pattern) {
  customTypePatterns[name] = pattern;
}

@visibleForTesting
clearCustomPatterns() {
  customTypePatterns.clear();
  _globalParamPatterns.clear();
}
