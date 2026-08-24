import 'dart:io';

import 'package:routed_views/src/translation/locale_resolution.dart';

/// Built-in locale resolvers backed by query parameters, cookies, sessions,
/// and headers.
///
/// A resolver returns one candidate locale or `null` when its source does not
/// provide a usable value. Applications can add their own source by
/// implementing this interface:
///
/// ```dart
/// class AccountLocaleResolver implements LocaleResolver {
///   @override
///   String? resolve(LocaleResolutionContext context) =>
///       sanitizeLocale(context.sessionValue?.call('account_locale'));
/// }
/// ```
// LocaleResolver is intentionally a public interface so applications can add
// resolution sources without changing the built-in resolver chain.
// ignore: one_member_abstracts
abstract class LocaleResolver {
  /// Attempts to resolve one locale from [context].
  ///
  /// Returns `null` when the resolver cannot produce a value.
  String? resolve(LocaleResolutionContext context);
}

/// Resolves a locale from a query parameter such as `?lang=fr`.
///
/// The value is trimmed and underscores are converted to dashes by
/// [sanitizeLocale]. An absent or blank parameter produces `null`.
class QueryLocaleResolver implements LocaleResolver {
  /// Creates a resolver for the locale query [parameter].
  QueryLocaleResolver({required this.parameter});

  /// Name of the query parameter containing the requested locale.
  final String parameter;

  @override
  String? resolve(LocaleResolutionContext context) {
    return sanitizeLocale(context.query(parameter));
  }
}

/// Resolves a locale from a cookie value.
///
/// Cookie values are passed through [sanitizeLocale].
class CookieLocaleResolver implements LocaleResolver {
  /// Creates a resolver for the locale [cookieName].
  CookieLocaleResolver({required this.cookieName});

  /// Name of the cookie containing the requested locale.
  final String cookieName;

  @override
  String? resolve(LocaleResolutionContext context) {
    return sanitizeLocale(context.cookie(cookieName));
  }
}

/// Resolves a locale from a session value.
///
/// If the request has no session integration, or the key is absent, this
/// resolver returns `null`. Values are passed through [sanitizeLocale].
class SessionLocaleResolver implements LocaleResolver {
  /// Creates a resolver for the locale [sessionKey].
  SessionLocaleResolver({required this.sessionKey});

  /// Key containing the requested locale in the current session.
  final String sessionKey;

  @override
  String? resolve(LocaleResolutionContext context) {
    final lookup = context.sessionValue;
    if (lookup == null) {
      return null;
    }
    return sanitizeLocale(lookup(sessionKey));
  }
}

/// Resolves the highest-weight locale from an `Accept-Language` header.
///
/// Entries may include `q` weights, for example
/// `fr-CA, fr;q=0.8, en;q=0.5`. Weights are clamped to the inclusive range
/// `0..1`; entries without a weight default to `1`. The first usable entry
/// after sorting by weight is returned, and its underscores are converted to
/// dashes by [sanitizeLocale].
class HeaderLocaleResolver implements LocaleResolver {
  /// Creates a resolver for [headerName].
  ///
  /// The default is the standard `Accept-Language` header.
  HeaderLocaleResolver({this.headerName = HttpHeaders.acceptLanguageHeader});

  /// Header containing weighted locale preferences.
  final String headerName;

  @override
  String? resolve(LocaleResolutionContext context) {
    final raw = context.header(headerName);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final candidates = raw
        .split(',')
        .map(_parseWeighted)
        .whereType<_Weighted>();
    final sorted = candidates.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    for (final entry in sorted) {
      final sanitized = sanitizeLocale(entry.value);
      if (sanitized != null) {
        return sanitized;
      }
    }
    return null;
  }

  _Weighted? _parseWeighted(String part) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final segments = trimmed.split(';');
    final value = segments.first.trim();
    var weight = 1.0;
    for (final directive in segments.skip(1)) {
      final normalized = directive.trim();
      if (normalized.startsWith('q=')) {
        final parsed = double.tryParse(normalized.substring(2));
        if (parsed != null) {
          weight = parsed.clamp(0, 1).toDouble();
        }
      }
    }
    return _Weighted(value, weight);
  }
}

class _Weighted {
  const _Weighted(this.value, this.weight);

  final String value;
  final double weight;
}

/// Normalizes an incoming locale string to the package's basic locale form.
///
/// Trimming whitespace and replacing `_` with `-` makes values such as
/// ` es_MX ` resolve as `es-MX`. `null` and blank input return `null`. This
/// helper does not verify that the result is a valid BCP 47 tag or that the
/// application has translations for it.
String? sanitizeLocale(String? input) {
  if (input == null) {
    return null;
  }
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll('_', '-');
}
