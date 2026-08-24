import 'package:routed_core/routed_core.dart';

/// Adds view-oriented translation helpers to [EngineContext].
///
/// Import `package:routed_views/routed_views.dart` to use these aliases from a
/// request handler or view helper:
///
/// ```dart
/// final greeting = ctx.viewTrans(
///   'messages.greeting',
///   replacements: {'name': 'Ada'},
/// );
/// final itemLabel = ctx.viewTransChoice('messages.items', 3);
/// ```
extension RoutedViewTranslation on EngineContext {
  /// Whether this context exposes the translation extension methods.
  ///
  /// This is a compile-time capability marker. It does not verify that a
  /// translator has been registered or that a requested key exists.
  bool get hasTranslationSupport => true;

  /// Resolves [key] using the translator associated with this context.
  ///
  /// [replacements] are applied to string values, [locale] overrides the
  /// context's current locale for this lookup, and [fallback] controls whether
  /// the configured fallback locale may be consulted.
  ///
  /// The result can be a string, scalar, nested map, or the unresolved key,
  /// depending on the translation data and translator configuration.
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

  /// Selects the pluralized translation for [key] and [count].
  ///
  /// The count is also available as the `count` replacement unless
  /// [replacements] supplies that key explicitly.
  String viewTransChoice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) => transChoice(key, count, replacements: replacements, locale: locale);
}
