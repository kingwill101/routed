/// Contract for locale-aware translation and pluralization services.
abstract class TranslatorContract {
  /// Locale used for translations when no locale is supplied to a call.
  String get locale;

  /// Changes the default translation locale.
  set locale(String value);

  /// Locale tried when a key is missing in [locale].
  String? get fallbackLocale;

  /// Changes the fallback locale.
  set fallbackLocale(String? value);

  /// Whether [key] resolves in the selected locale or its fallback.
  bool has(String key, {String? locale, bool fallback = true});

  /// Whether [key] resolves in the specific [locale] without fallback.
  bool hasForLocale(String key, String locale);

  /// Translates [key], applying optional [replacements].
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  });

  /// Selects a pluralized translation for [key] and [count].
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  });

  /// Adds already-loaded [lines] for [locale] and [namespace].
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  });

  /// Installs a callback for missing translation keys.
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  );
}
