/// Built-in locale resolvers backed by query params, cookies, sessions, and
/// headers.
library;

import 'dart:io';

import 'package:routed/src/translation/locale_resolution.dart';

/// Contract implemented by all locale resolvers.
abstract class LocaleResolver {
  /// Attempts to resolve a locale from the provided [context].
  ///
  /// Returns `null` when the resolver cannot produce a value.
  String? resolve(LocaleResolutionContext context);
}

/// Resolves locales from a query parameter (e.g. `?lang=fr`).
class QueryLocaleResolver implements LocaleResolver {
  QueryLocaleResolver({required this.parameter});

  final String parameter;

  @override
  String? resolve(LocaleResolutionContext context) {
    return sanitizeLocale(context.query(parameter));
  }
}

/// Resolves locales from a cookie value.
class CookieLocaleResolver implements LocaleResolver {
  CookieLocaleResolver({required this.cookieName});

  final String cookieName;

  @override
  String? resolve(LocaleResolutionContext context) {
    return sanitizeLocale(context.cookie(cookieName));
  }
}

/// Resolves locales from a session key.
class SessionLocaleResolver implements LocaleResolver {
  SessionLocaleResolver({required this.sessionKey});

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

/// Resolves locales from the `Accept-Language` header.
class HeaderLocaleResolver implements LocaleResolver {
  HeaderLocaleResolver({this.headerName = HttpHeaders.acceptLanguageHeader});

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
    var value = segments.first.trim();
    double weight = 1.0;
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

/// Normalises incoming locale strings by trimming whitespace and using dashes.
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
