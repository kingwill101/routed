part of 'engine.dart';

/// {@template engine_route}
/// The final route structure after combining everything:
/// - method, [path], [name]
/// - [middlewares]: engine-level + route.finalMiddlewares
///
/// This class represents a compiled and configured route within the routing engine.
/// {@endtemplate}
class EngineRoute {
  /// HTTP method (GET, POST, etc.).
  final String method;

  /// URL path pattern.
  ///
  /// Defines the URL structure that this route matches. Supports parameters and
  /// wildcards.
  final String path;

  /// Optional route name for URL generation.
  ///
  /// Can be used to generate URLs pointing to this route.
  final String? name;

  /// Request handler function.
  ///
  /// This function is executed when a request matches this route.
  final Handler handler;

  /// List of middleware to apply.
  ///
  /// These middlewares are executed in order before the route's handler.
  final List<Middleware> middlewares;

  /// Compiled regex pattern for matching URLs.
  final RegExp _uriPattern;

  /// Map of parameter names to their type info.
  final Map<String, ParamInfo> _parameterPatterns;

  /// Route constraints for additional matching rules.
  ///
  /// Allows for more complex route matching beyond simple path and method.
  final Map<String, dynamic> constraints;

  /// Whether this is a fallback route.
  ///
  /// Fallback routes match any request that doesn't match any other route.
  final bool isFallback;

  /// Creates a new route with the given properties.
  EngineRoute({
    required this.method,
    required this.path,
    required this.handler,
    this.name,
    this.middlewares = const [],
    this.constraints = const {},
    this.isFallback = false,
  }) : _uriPattern = _buildUriPattern(path).pattern,
       _parameterPatterns = _buildUriPattern(path).paramInfo;

  /// Creates a fallback route.
  EngineRoute.fallback({required this.handler, this.middlewares = const []})
    : method = '*',
      path = '*',
      name = null,
      constraints = const {},
      isFallback = true,
      _uriPattern = RegExp('.*'),
      _parameterPatterns = const {};

  /// Checks if a request matches this route.
  bool matches(HttpRequest request) {
    final match = tryMatch(request);
    return match?.matched ?? false;
  }

  /// Attempts to match a request to this route.
  ///
  /// If [checkMethodOnly] is true, only the HTTP method is checked.
  RouteMatch? tryMatch(HttpRequest request, {bool checkMethodOnly = false}) {
    // If this is a fallback route, match any path and ignore the method.
    if (isFallback) {
      return RouteMatch(matched: true, isMethodMismatch: false, route: this);
    }

    // For non-fallback routes, check path and method.
    final pathMatches =
        _uriPattern.hasMatch(request.uri.path.split("?")[0]) ||
        _uriPattern.hasMatch("${request.uri.path}/");

    if (!pathMatches) {
      return RouteMatch(matched: false, isMethodMismatch: false);
    }

    if (method != request.method) {
      return RouteMatch(matched: false, isMethodMismatch: true);
    }

    if (checkMethodOnly) {
      return RouteMatch(matched: true, isMethodMismatch: false);
    }

    final constraintsValid = validateConstraints(request);
    return RouteMatch(
      matched: constraintsValid,
      isMethodMismatch: false,
      route: this,
    );
  }

  /// Extracts parameters with their type information from a URI.
  List<({String key, dynamic value, ParamInfo info})> paramsWithInfo(
    String uri,
  ) {
    final match =
        _uriPattern.firstMatch(uri) ?? _uriPattern.firstMatch("$uri/");
    if (match == null) return [];

    return _parameterPatterns.entries.map((entry) {
      final key = entry.key;
      final info = entry.value;
      final rawValue = match.namedGroup(key);
      // Handle null values based on parameter info
      if (rawValue == null && !info.isOptional) {
        return (key: key, value: null, info: ParamInfo(type: 'string'));
      }

      String? decodedValue;
      if (rawValue != null) {
        try {
          decodedValue = Uri.decodeComponent(rawValue);
        } catch (e) {
          // If decoding fails, use the raw value instead
          decodedValue = rawValue;
        }
      }

      return (
        key: key,
        value: _castParameter(decodedValue, info.type),
        info: info,
      );
    }).toList();
  }

  /// Extracts parameters from a URI string.
  Map<String, dynamic> extractParameters(String uri) {
    final match =
        _uriPattern.firstMatch(uri) ?? _uriPattern.firstMatch("$uri/");
    if (match == null) return {};

    return _parameterPatterns.map((key, info) {
      final rawValue = match.namedGroup(key);
      // Handle null values based on parameter info
      if (rawValue == null && !info.isOptional) {
        return MapEntry(key, null);
      }

      String? decodedValue;
      if (rawValue != null) {
        try {
          decodedValue = Uri.decodeComponent(rawValue);
        } catch (e) {
          // If decoding fails, use the raw value instead
          decodedValue = rawValue;
        }
      }

      return MapEntry(key, _castParameter(decodedValue, info.type));
    });
  }

  /// A map of custom casting functions that can be registered for specific types.
  static final Map<String, dynamic Function(String?)> _customCastingFunctions =
      {};

  /// Registers a custom casting function for the given type.
  ///
  /// {@macro custom_casting}
  static void registerCustomCasting(
    String type,
    dynamic Function(String?) castingFunction,
  ) {
    _customCastingFunctions[type] = castingFunction;
  }

  /// Unregisters a custom casting function for the given type.
  static void unregisterCustomCasting(String type) {
    _customCastingFunctions.remove(type);
  }

  /// Casts a parameter value to the correct type.
  static dynamic _castParameter(String? value, String type) {
    if (value == null) return null;

    final aType = getTypeDefinition(type);

    if (aType != null) {
      return aType.cast(value);
    }

    // Check for custom casting function
    if (_customCastingFunctions.containsKey(type)) {
      return _customCastingFunctions[type]!(value);
    }

    return value;
  }

  /// {@template custom_casting}
  /// To register a custom casting type you must use [EngineRoute.registerCustomCasting].
  ///
  /// This allows you to define how route parameters are converted from their
  /// string representation to a specific Dart type.
  ///
  /// Example:
  /// ```dart
  /// EngineRoute.registerCustomCasting('bool', (String? value) => value == 'true');
  /// ```
  /// {@endtemplate}
  /// Validates route constraints against a request.
  bool validateConstraints(HttpRequest request) {
    // Get route params extracted at runtime
    final routeParams = extractParameters(request.uri.path);

    return constraints.entries.every((entry) {
      final key = entry.key;
      final constraint = entry.value;

      // Special-case: domain constraint
      if (key == 'domain' && constraint is String) {
        return RegExp(constraint).hasMatch(request.headers.host ?? '');
      }

      // Special-case: function constraint
      if (constraint is bool Function(HttpRequest)) {
        return constraint(request);
      }

      // Otherwise, treat constraint as a regex pattern for the same-named path param
      /// {@macro custom_casting}
      final paramValue = routeParams[key];
      if (paramValue == null) {
        // If the param doesn't exist, decide how to handle
        return false;
      }

      // If our constraint is a string, interpret it as a regex
      if (constraint is String) {
        return RegExp(constraint).hasMatch(paramValue.toString());
      }

      // If not recognized, assume it's OK or handle it however you like
      return true;
    });
  }

  @override
  String toString() {
    final mwCount = middlewares.isEmpty ? 0 : middlewares.length;
    final name = this.name != null ? "with name \"${this.name}\"" : "";
    return '[$method] $path $name [middlewares: $mwCount]';
  }

  /// Builds a regex pattern for matching URIs.
  static _PatternData _buildUriPattern(String uri) {
    // If this is the fallback route, return a regex that matches everything.
    if (uri == '*' || uri == '/{__fallback:*}') {
      return _PatternData(RegExp('.*'), {});
    }

    final paramInfo = <String, ParamInfo>{};
    var pattern = uri;

    // Handle optional parameters e.g. {param?}
    pattern = pattern.replaceAllMapped(RegExp(r'{(\w+)\?}'), (m) {
      final paramName = m.group(1)!;
      paramInfo[paramName] = ParamInfo(type: 'string', isOptional: true);
      return '(?:/{0,1}(?<$paramName>[^/]+))?';
    });

    // Handle wildcard parameters with leading '*' e.g. {*param}
    pattern = pattern.replaceAllMapped(RegExp(r'{[*](\w+)}'), (m) {
      final paramName = m.group(1)!;
      paramInfo[paramName] = ParamInfo(type: 'string', isWildcard: true);
      return '(?<$paramName>.*)';
    });

    // Handle normal parameters with an optional explicit type e.g. {id:int}
    pattern = pattern.replaceAllMapped(RegExp(r'{(\w+)(?::(\w+))?}'), (m) {
      final paramName = m.group(1)!;
      final explicitType = m.group(2);

      // If no explicit type, check for global param pattern
      final globalPattern = getGlobalParamPattern(paramName);
      final effectivePattern = explicitType != null
          ? getPattern(explicitType)
          : globalPattern;

      paramInfo[paramName] = ParamInfo(
        type: explicitType ?? 'string',
        isOptional: false,
        isWildcard: false,
      );

      return '(?<$paramName>${effectivePattern ?? r'[^/]+'})';
    });

    return _PatternData(RegExp('^$pattern\$'), paramInfo);
  }
}

class ParamInfo {
  final String type;
  final bool isOptional;
  final bool isWildcard;

  ParamInfo({
    required this.type,
    this.isOptional = false,
    this.isWildcard = false,
  });
}

class _PatternData {
  final RegExp pattern;
  final Map<String, ParamInfo> paramInfo;

  _PatternData(this.pattern, this.paramInfo);
}

extension on Engine {
  // Method to generate URL for a named route
  // ignore: unused_element
  String route(String name, [Map<String, dynamic>? params]) {
    final route = getAllRoutes().where((r) => r.name == name).firstOrNull;

    if (route == null) {
      throw Exception('Route $name not found');
    }

    var path = route.path;
    if (params != null) {
      params.forEach((key, value) {
        path = path.replaceAll(':$key', value.toString());
        path = path.replaceAll('{$key}', value.toString());
      });
    }

    return path;
  }
}
