import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/translation/translator.dart';
import 'package:routed/src/translation/constants.dart';

import 'zone.dart';

T config<T>(String key, [T? defaultValue]) {
  final value = AppZone.config.get(key, defaultValue);
  return value is T ? value : defaultValue as T;
}

// Engine get engine => AppZone.engine;
//
// EngineConfig get engineConfig => AppZone.engineConfig;

String route(String name, [Map<String, dynamic>? parameters]) {
  return AppZone.route(name, parameters);
}

/// Translates [key] using the current request locale.
///
/// `replacements` interpolate placeholders such as `:name`. Pass [locale] to
/// override the locale or set [fallback] to `false` to disable fallback
/// traversal.
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
///
/// The resolved locale follows the same rules as [trans].
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
///
/// When the middleware is unavailable, [defaultLocale] (or `'en'`) is used.
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

TranslatorContract? _translatorOrNull() {
  try {
    final ctx = AppZone.context;
    final container = ctx.container;
    final resolved = _translatorFromContainer(container);
    if (resolved != null) {
      return resolved;
    }
  } catch (_) {}
  try {
    final engine = AppZone.engine;
    return _translatorFromContainer(engine.container);
  } catch (_) {
    return null;
  }
}

TranslatorContract? _translatorFromContainer(Container container) {
  if (!container.has<TranslatorContract>()) {
    return null;
  }
  try {
    return container.get<TranslatorContract>();
  } catch (_) {
    return null;
  }
}

String? _currentLocaleOverride() {
  try {
    final ctx = AppZone.context;
    final stored = ctx.get<String>(kRequestLocaleAttribute);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
  } catch (_) {}
  return null;
}
