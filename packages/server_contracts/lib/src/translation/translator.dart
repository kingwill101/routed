/// Resolves locale-aware messages and pluralized translations.
///
/// Keys conventionally use `group.item` for grouped resources and
/// `namespace::group.item` for namespaced resources. Implementations may also
/// return nested maps when a key addresses a group rather than a single line.
/// The contract is synchronous so validation, middleware, and view rendering
/// can use it without introducing asynchronous control flow.
abstract class TranslatorContract {
  /// Default locale used when a method does not receive an explicit locale.
  String get locale;

  /// Changes the default locale used for subsequent lookups.
  set locale(String value);

  /// Locale tried after the requested locale does not contain a key.
  String? get fallbackLocale;

  /// Changes or clears the fallback locale.
  set fallbackLocale(String? value);

  /// Whether [key] resolves in the selected locale or its fallback.
  ///
  /// An explicit [locale] overrides the default locale for this call. Set
  /// [fallback] to `false` to restrict the lookup to that locale.
  bool has(String key, {String? locale, bool fallback = true});

  /// Whether [key] resolves in [locale] without consulting a fallback locale.
  bool hasForLocale(String key, String locale);

  /// Resolves [key], applying optional placeholder [replacements].
  ///
  /// [locale] overrides the default locale for this call. When [fallback] is
  /// enabled, [fallbackLocale] is tried after the requested locale. A resolved
  /// value may be a string, scalar, or nested map. If no value exists, the
  /// implementation should invoke its missing-key handler and then return the
  /// key when the handler does not provide a replacement.
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  });

  /// Selects the pluralized translation branch for [key] and [count].
  ///
  /// The concrete translator defines the pluralization syntax. [count] is
  /// also available to the selected line as the `count` replacement unless
  /// [replacements] supplies that key explicitly.
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  });

  /// Adds already-loaded [lines] for [locale] and [namespace].
  ///
  /// Grouped keys should use the `group.item` form. The default `*` namespace
  /// represents application translations rather than a vendor namespace.
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  });

  /// Installs or clears the callback used for missing translation keys.
  ///
  /// The callback receives the unresolved `key` and locale being searched. A
  /// non-null callback result becomes the translation; returning `null` keeps
  /// the normal missing-key behavior, usually returning the key itself.
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  );
}
