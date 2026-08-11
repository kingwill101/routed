part of 'context.dart';

/// Helper methods that mirror AppZone helpers but operate on EngineContext.
extension EngineContextHelpers on EngineContext {
  /// Retrieves a configuration value for this request.
  T config<T>(String key, [T? defaultValue]) {
    final resolved = _resolveConfig();
    if (resolved == null) {
      return defaultValue as T;
    }
    final value = resolved.get<T>(key, defaultValue);
    return value is T ? value : defaultValue as T;
  }

  /// Generates a route URL by name.
  String route(String name, [Map<String, dynamic>? parameters]) {
    final engine = this.engine;
    if (engine == null) {
      throw StateError('Route "$name" not available without an Engine');
    }
    final path = engine.route(name, parameters);
    if (path == null) {
      throw StateError('Route "$name" not found for this context');
    }
    return path;
  }

  /// Translates [key] using the current request locale.
  Object? trans(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  }) {
    final translator = _translatorOrNull();
    if (translator == null) {
      return key;
    }
    final resolvedLocale =
        locale ?? _currentLocaleOverride() ?? translator.locale;
    return translator.translate(
      key,
      replacements: replacements,
      locale: resolvedLocale,
      fallback: fallback,
    );
  }

  /// Translates [key] using pluralization rules and the supplied [count].
  String transChoice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) {
    final translator = _translatorOrNull();
    if (translator == null) {
      return key;
    }
    final resolvedLocale =
        locale ?? _currentLocaleOverride() ?? translator.locale;
    return translator.choice(
      key,
      count,
      replacements: replacements,
      locale: resolvedLocale,
    );
  }

  /// Returns the locale currently associated with the request.
  String currentLocale([String? defaultLocale]) {
    final override = _currentLocaleOverride();
    if (override != null) {
      return override;
    }
    final translator = _translatorOrNull();
    if (translator != null) {
      return translator.locale;
    }
    return defaultLocale ?? 'en';
  }

  Config? _resolveConfig() {
    final container = _containerOrNull();
    final fromContainer = _configFromContainer(container);
    if (fromContainer != null) {
      return fromContainer;
    }
    final engine = this.engine;
    if (engine == null) {
      return null;
    }
    return _configFromContainer(engine.container);
  }

  Config? _configFromContainer(Container? container) {
    if (container == null) {
      return null;
    }
    if (!container.has<Config>()) {
      return null;
    }
    try {
      return container.get<Config>();
    } catch (_) {
      return null;
    }
  }

  TranslatorContract? _translatorOrNull() {
    final container = _containerOrNull();
    final resolved = _translatorFromContainer(container);
    if (resolved != null) {
      return resolved;
    }
    final engine = this.engine;
    if (engine == null) {
      return null;
    }
    return _translatorFromContainer(engine.container);
  }

  TranslatorContract? _translatorFromContainer(Container? container) {
    if (container == null) {
      return null;
    }
    if (!container.has<TranslatorContract>()) {
      return null;
    }
    try {
      return container.get<TranslatorContract>();
    } catch (_) {
      return null;
    }
  }

  Container? _containerOrNull() {
    try {
      return container;
    } catch (_) {
      return null;
    }
  }

  String? _currentLocaleOverride() {
    final stored = get<String>('routed.locale');
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return null;
  }

  Response json(Object? data, {int statusCode = 200}) {
    response.statusCode = statusCode;
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
    response.write(jsonEncode(data));
    return response;
  }

  Response string(String content, {int statusCode = 200}) {
    response.statusCode = statusCode;
    response.write(content);
    return response;
  }

  Response html(String content, {int statusCode = 200}) {
    response.statusCode = statusCode;
    response.headers.set('Content-Type', 'text/html; charset=utf-8');
    response.write(content);
    return response;
  }

  Future<Response> redirect(String location, {int statusCode = HttpStatus.found}) async {
    response.statusCode = statusCode;
    response.headers.set(HttpHeaders.locationHeader, location);
    return response;
  }
}
