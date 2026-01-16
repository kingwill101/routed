import 'package:routed/src/container/container.dart';
import 'package:routed/src/router/middleware_reference.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/support/named_registry.dart';

/// Creates a [Middleware] using the provided [container].
///
/// This function signature is used to lazily instantiate middleware, allowing
/// access to container services during middleware construction.
typedef MiddlewareFactory = Middleware Function(Container container);

/// Stores middleware factories and resolves [MiddlewareReference] placeholders.
///
/// A registry maps string identifiers to [MiddlewareFactory] instances. It can
/// build middleware objects on demand and replace placeholder references in
/// middleware lists.
///
/// This is useful for defining middleware by name in configuration files or
/// route definitions, then resolving them to actual instances at runtime.
///
/// Example:
/// ```dart
/// final registry = MiddlewareRegistry();
/// registry.register('auth', (container) => AuthMiddleware());
///
/// // Later, resolve a middleware reference
/// final middleware = registry.build('auth', container);
/// ```
class MiddlewareRegistry extends NamedRegistry<MiddlewareFactory> {
  MiddlewareRegistry();

  /// Registers a new middleware [factory] under [id].
  ///
  /// If a factory is already registered with the same [id], the old factory
  /// is silently replaced with the new one.
  ///
  /// Example:
  /// ```dart
  /// registry.register('logging', (container) {
  ///   return LoggingMiddleware(container.get<Logger>());
  /// });
  /// ```
  void register(String id, MiddlewareFactory factory) {
    registerEntry(id, factory);
  }

  /// Whether a factory is registered under [id].
  ///
  /// Returns `true` if a middleware factory has been registered with this
  /// identifier, `false` otherwise.
  bool has(String id) => containsEntry(id);

  /// Builds a middleware instance using the factory registered under [id].
  ///
  /// Returns `null` if no factory is associated with [id]. The [container]
  /// is passed to the factory function to enable dependency injection.
  ///
  /// Example:
  /// ```dart
  /// final middleware = registry.build('auth', container);
  /// if (middleware != null) {
  ///   // Use the middleware
  /// }
  /// ```
  Middleware? build(String id, Container container) {
    final factory = getEntry(id);
    if (factory == null) return null;
    final middleware = factory(container);
    MiddlewareReference.tag(middleware, id);
    return middleware;
  }

  /// All registered middleware identifiers.
  ///
  /// Returns an iterable of all string identifiers that have been registered
  /// with this registry.
  Iterable<String> get ids => entryNames;

  /// Resolves a single [middleware], handling [MiddlewareReference] placeholders.
  ///
  /// If [middleware] is a placeholder (a [MiddlewareReference]), the corresponding
  /// factory is used to build a concrete instance using the provided [container].
  ///
  /// Throws a [StateError] when a placeholder refers to a non-existent registration.
  /// If [middleware] is not a placeholder, returns it unchanged.
  ///
  /// Example:
  /// ```dart
  /// final ref = MiddlewareReference('auth');
  /// final resolved = registry.resolveMiddleware(ref, container);
  /// // resolved is now an AuthMiddleware instance
  /// ```
  Middleware resolveMiddleware(Middleware middleware, Container container) {
    final name = MiddlewareReference.lookup(middleware);
    if (name != null && name.isNotEmpty) {
      final built = build(name, container);
      if (built == null) {
        final available = ids.isEmpty ? 'none' : ids.join(', ');
        throw StateError(
          'Middleware "$name" is not registered. '
          'Available middleware: $available',
        );
      }
      return built;
    }
    return middleware;
  }

  /// Resolves a list of [middlewares], returning a new list with placeholders replaced.
  ///
  /// This creates a new list where each [MiddlewareReference] placeholder is
  /// replaced with its corresponding middleware instance. Non-placeholder
  /// middleware are copied to the new list unchanged.
  ///
  /// Example:
  /// ```dart
  /// final middlewares = [
  ///   MiddlewareReference('auth'),
  ///   MiddlewareReference('logging'),
  ///   CustomMiddleware(),
  /// ];
  /// final resolved = registry.resolveAll(middlewares, container);
  /// ```
  List<Middleware> resolveAll(
    Iterable<Middleware> middlewares,
    Container container,
  ) {
    return middlewares
        .map((middleware) => resolveMiddleware(middleware, container))
        .toList();
  }

  /// Resolves placeholders in place within a mutable [middlewares] list.
  ///
  /// This modifies the provided [middlewares] list directly, replacing each
  /// [MiddlewareReference] with its corresponding middleware instance.
  /// This is more efficient than [resolveAll] when you don't need to preserve
  /// the original list.
  ///
  /// Example:
  /// ```dart
  /// final middlewares = [MiddlewareReference('auth')];
  /// registry.resolveInPlace(middlewares, container);
  /// // middlewares now contains the actual AuthMiddleware instance
  /// ```
  void resolveInPlace(List<Middleware> middlewares, Container container) {
    for (var i = 0; i < middlewares.length; i++) {
      middlewares[i] = resolveMiddleware(middlewares[i], container);
    }
  }
}
