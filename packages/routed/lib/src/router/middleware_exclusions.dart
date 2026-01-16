import 'package:routed/src/router/middleware_reference.dart';
import 'package:routed/src/router/types.dart';

/// Tracks middleware exclusions for routes and groups.
class MiddlewareExclusions {
  final Set<String> _ids = {};
  final Set<Middleware> _middlewares = {};

  bool get isEmpty => _ids.isEmpty && _middlewares.isEmpty;

  Set<String> get ids => _ids;

  Set<Middleware> get middlewares => _middlewares;

  /// Adds middleware exclusions by name or by middleware instance.
  void addAll(Iterable<Object> middlewares) {
    for (final middleware in middlewares) {
      _add(middleware);
    }
  }

  /// Merges another exclusion set into this one.
  void mergeIn(MiddlewareExclusions other) {
    _ids.addAll(other._ids);
    _middlewares.addAll(other._middlewares);
  }

  /// Returns a new exclusion set with [other] merged in.
  MiddlewareExclusions merged(MiddlewareExclusions other) {
    final merged = MiddlewareExclusions();
    merged.mergeIn(this);
    merged.mergeIn(other);
    return merged;
  }

  /// Returns true if [middleware] should be excluded.
  bool excludes(Middleware middleware) {
    if (_middlewares.contains(middleware)) {
      return true;
    }
    final name =
        MiddlewareReference.lookupTag(middleware) ??
        MiddlewareReference.lookup(middleware);
    return name != null && _ids.contains(name);
  }

  /// Filters [source], removing excluded middlewares.
  List<Middleware> filter(Iterable<Middleware> source) {
    if (isEmpty) {
      return List<Middleware>.from(source);
    }
    return source.where((middleware) => !excludes(middleware)).toList();
  }

  void _add(Object middleware) {
    if (middleware is String) {
      _ids.add(middleware);
      return;
    }
    if (middleware is Middleware) {
      final name =
          MiddlewareReference.lookupTag(middleware) ??
          MiddlewareReference.lookup(middleware);
      if (name != null && name.isNotEmpty) {
        _ids.add(name);
      } else {
        _middlewares.add(middleware);
      }
      return;
    }
    throw ArgumentError.value(
      middleware,
      'middleware',
      'Expected a middleware function or middleware identifier.',
    );
  }
}
