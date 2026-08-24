import 'package:routed_core/routed_core.dart' show EngineContext;

/// Looks up a named value from one request source.
///
/// Return `null` when the source does not contain [name]. The lookup itself
/// does not sanitize locale values; the built-in resolvers call
/// `sanitizeLocale` after reading them.
typedef LocaleLookup = String? Function(String name);

/// Provides request-source lookups to locale resolvers.
///
/// A context keeps header, query, cookie, and optional session access behind a
/// small synchronous interface. It does not choose a precedence order; the
/// order is defined by the locale manager's resolver list.
///
/// ```dart
/// final context = LocaleResolutionContext(
///   header: (name) => requestHeaders[name],
///   query: (name) => queryParameters[name],
///   cookie: (name) => cookies[name],
/// );
/// final requested = context.query('lang');
/// ```
class LocaleResolutionContext {
  /// Creates a context with lookups for each request source.
  ///
  /// [sessionValue] may be omitted when sessions are not available for the
  /// current request.
  LocaleResolutionContext({
    required this.header,
    required this.query,
    required this.cookie,
    this.sessionValue,
  });

  /// Builds a context from the request represented by [ctx].
  ///
  /// Header lookup follows HTTP header name semantics. Cookie and query
  /// lookups return the first matching request value. The session lookup
  /// returns `null` when sessions are unavailable or do not contain the key.
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
        return (ctx as dynamic).getSession<String>(key) as String?;
      } on Object catch (_) {
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

  /// Looks up a request header by name.
  final LocaleLookup header;

  /// Looks up a request query parameter by name.
  final LocaleLookup query;

  /// Looks up a request cookie by name.
  final LocaleLookup cookie;

  /// Looks up a value in the current session, when sessions are enabled.
  ///
  /// This callback is `null` when no session integration is available.
  final LocaleLookup? sessionValue;
}
