library;

import 'package:routed/src/context/context.dart';
import 'package:routed_core/routed_core.dart' as core;

export 'package:routed_core/routed_core.dart' show LocaleLookup;

/// Routed compatibility wrapper that keeps `fromContext` while delegating the
/// underlying locale-resolution model to `routed_core`.
class LocaleResolutionContext extends core.LocaleResolutionContext {
  LocaleResolutionContext({
    required super.header,
    required super.query,
    required super.cookie,
    super.sessionValue,
  });

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
