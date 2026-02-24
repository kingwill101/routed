abstract class TranslatorContract {
  String get locale;

  set locale(String value);

  String? get fallbackLocale;

  set fallbackLocale(String? value);

  bool has(String key, {String? locale, bool fallback = true});

  bool hasForLocale(String key, String locale);

  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  });

  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  });

  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  });

  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  );
}
