/// Utilities for exposing header, query, cookie, and session lookups when
/// resolving locales.
library;

import 'package:routed/src/context/context.dart';

/// Looks up a value by [name] from a particular source (headers, query, etc.).
typedef LocaleLookup = String? Function(String name);

/// Encapsulates the data available to locale resolvers.
class LocaleResolutionContext {
  /// Creates a context with individual lookups for each source.
  LocaleResolutionContext({
    required this.header,
    required this.query,
    required this.cookie,
    this.sessionValue,
  });

  /// Header lookup (case-insensitive).
  final LocaleLookup header;

  /// Query parameter lookup.
  final LocaleLookup query;

  /// Cookie lookup.
  final LocaleLookup cookie;

  /// Session lookup, if sessions are enabled.
  final LocaleLookup? sessionValue;

  /// Builds a context from the current [EngineContext].
  ///
  /// Header lookup is case-insensitive and the session lookup gracefully falls
  /// back to `null` when sessions are not configured.
  factory LocaleResolutionContext.fromContext(EngineContext ctx) {
    String? headerLookup(String name) {
      final values = ctx.request.headers[name];
      if (values == null || values.isEmpty) {
        return null;
      }
      return values.first;
    }

    String? cookieLookup(String name) {
      for (final cookie in ctx.request.cookies) {
        if (cookie.name == name) {
          return cookie.value;
        }
      }
      return null;
    }

    String? sessionLookup(String key) {
      try {
        return ctx.getSession<String>(key);
      } catch (_) {
        return null;
      }
    }

    return LocaleResolutionContext(
      header: headerLookup,
      query: (name) => ctx.request.queryParameters[name],
      cookie: cookieLookup,
      sessionValue: sessionLookup,
    );
  }
}
