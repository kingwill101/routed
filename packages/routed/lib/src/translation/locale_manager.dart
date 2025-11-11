/// Coordinates locale resolution across configured resolvers.
///
/// The manager evaluates resolvers in order until one yields a non-empty
/// locale. When every resolver fails, the default locale is returned.
library;

import 'package:routed/src/translation/locale_resolution.dart';
import 'package:routed/src/translation/resolvers.dart';

/// Chooses the active locale for each request.
class LocaleManager {
  /// Creates a manager with the provided [resolvers].
  ///
  /// Locales are resolved in order. If none of the resolvers match, the
  /// [defaultLocale] is returned. When translations are missing, callers can
  /// fall back to [fallbackLocale].
  LocaleManager({
    required this.defaultLocale,
    required this.fallbackLocale,
    required List<LocaleResolver> resolvers,
  }) : _resolvers = List.unmodifiable(resolvers);

  /// Preferred locale when the resolver chain produces no match.
  final String defaultLocale;

  /// Locale consulted when a translation key is unavailable in the primary
  /// locale.
  final String fallbackLocale;

  final List<LocaleResolver> _resolvers;

  /// Resolves the locale for the provided [context].
  ///
  /// Returns the first non-empty locale or [defaultLocale] when every resolver
  /// fails.
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
