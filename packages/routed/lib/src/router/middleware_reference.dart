import 'dart:async';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

/// Lightweight tag that records middleware identifiers for deferred resolution.
class MiddlewareReference {
  MiddlewareReference._();

  static final Expando<String> _names = Expando<String>('middlewareRef');

  /// Creates a placeholder middleware that must be resolved before execution.
  static Middleware create(String name) {
    FutureOr<Response> placeholder(EngineContext ctx, Next next) {
      throw UnimplementedError(
        'MiddlewareReference "$name" must be resolved before execution.',
      );
    }

    _names[placeholder] = name;
    return placeholder;
  }

  /// Returns the registered name for [middleware] if it is a reference.
  static String? lookup(Middleware middleware) => _names[middleware];

  /// Clears the marker for [middleware].
  static void clear(Middleware middleware) => _names[middleware] = null;
}

/// Convenience factory for constructing middleware references.
class MiddlewareRef {
  const MiddlewareRef._();

  static Middleware of(String name) => MiddlewareReference.create(name);
}
