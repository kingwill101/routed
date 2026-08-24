import 'package:routed_views/src/translation/locale_resolution.dart';
import 'package:routed_views/src/translation/resolvers.dart';

/// Resolves a request locale by walking an ordered resolver chain.
///
/// The first resolver that returns a non-empty value wins. Built-in resolvers
/// sanitize their values before returning them; custom [LocaleResolver]
/// implementations are responsible for returning a suitable locale. When
/// every resolver returns `null` or an empty string, [defaultLocale] is used.
///
/// ```dart
/// final manager = LocaleManager(
///   defaultLocale: 'en',
///   fallbackLocale: 'en',
///   resolvers: [
///     QueryLocaleResolver(parameter: 'lang'),
///     HeaderLocaleResolver(),
///   ],
/// );
/// final locale = manager.resolve(context);
/// ```
class LocaleManager {
  /// Creates a manager with the provided ordered [resolvers].
  ///
  /// If none of the resolvers match, [defaultLocale] is returned. The
  /// [fallbackLocale] is retained as localization configuration for the
  /// translator; this manager itself only resolves the request's primary
  /// locale.
  LocaleManager({
    required this.defaultLocale,
    required this.fallbackLocale,
    required List<LocaleResolver> resolvers,
  }) : _resolvers = List.unmodifiable(resolvers);

  /// Locale returned when the resolver chain produces no match.
  final String defaultLocale;

  /// Locale configured for translation lookups after the primary locale.
  ///
  /// [LocaleManager] does not perform translation lookup itself. The
  /// registered translator uses this value when a key is absent from the
  /// resolved locale.
  final String fallbackLocale;

  final List<LocaleResolver> _resolvers;

  /// Resolves the primary locale for the provided [context].
  ///
  /// Returns the first non-empty resolver result or [defaultLocale] when every
  /// resolver fails.
  String resolve(LocaleResolutionContext context) {
    for (final resolver in _resolvers) {
      final candidate = resolver.resolve(context);
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return defaultLocale;
  }
}
