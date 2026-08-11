import 'package:routed_core/routed_core.dart';

/// Translation extensions for [EngineContext] — migrated from
/// `routed` `src/context/helpers.dart` per refactor.md §16.2.
/// Delegates to the existing `trans`/`transChoice` on `EngineContext` so
/// callers can `import 'package:routed_views/routed_views.dart'` and get
/// translation helpers without importing `routed` view internals.
extension RoutedViewTranslation on EngineContext {
  /// Whether translation support is available in this context.
  bool get hasTranslationSupport => true;

  /// Alias for `trans` that makes the `routed_views` ownership explicit.
  Object? viewTrans(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  }) => trans(
    key,
    replacements: replacements,
    locale: locale,
    fallback: fallback,
  );

  /// Alias for `transChoice`.
  String viewTransChoice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) => transChoice(key, count, replacements: replacements, locale: locale);
}
