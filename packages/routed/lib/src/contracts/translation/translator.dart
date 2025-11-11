/// Contract describing translation lookups within Routed applications.
///
/// The translator is responsible for resolving dot-notated keys,
/// performing placeholder substitutions, handling locale fallbacks, and
/// providing pluralization helpers. It is intentionally synchronous so that
/// validation rules, templates, and middleware can consume translations
/// without complicating their control flow.
abstract class TranslatorContract {
  /// Default locale for lookups when none is provided.
  String get locale;

  set locale(String value);

  /// Fallback locale used when the primary locale does not contain a key.
  String? get fallbackLocale;

  set fallbackLocale(String? value);

  /// Determines whether a translation exists.
  bool has(
    String key, {
    String? locale,
    bool fallback = true,
  });

  /// Determines whether a translation exists for a specific locale without
  /// considering fallbacks.
  bool hasForLocale(String key, String locale);

  /// Resolves the translation line for [key].
  ///
  /// Returns the translated value (which may be a string or nested map) or
  /// the key itself when no translation exists.
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  });

  /// Resolves a pluralized translation string using the configured selector.
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  });

  /// Registers ad-hoc lines for the given [locale] and [namespace]. The
  /// [lines] map should contain entries in `group.key` form.
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  });

  /// Registers a callback that will be invoked whenever a missing translation
  /// key is encountered. Returning a non-null value from the callback will be
  /// used as the translated line.
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  );
}
