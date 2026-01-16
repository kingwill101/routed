import 'package:routed/src/router/router.dart';

/// The `RouterGroupBuilder` class is used to build and configure a group of routes within a router.
/// This class is returned by the `router.group(...)` method, allowing you to chain additional
/// configuration methods such as `.name("myGroup")`.
class RouterGroupBuilder {
  /// A reference to the router instance that this group belongs to.
  final Router _router;

  /// Constructs a `RouterGroupBuilder` with the given router instance.
  ///
  /// The [router] parameter is the router instance that this group will be associated with.
  RouterGroupBuilder(this._router);

  /// Sets the name of the route group.
  ///
  /// The [groupName] parameter specifies the name to be assigned to the route group.
  /// This method updates the `groupName` property of the router instance and returns
  /// the current `RouterGroupBuilder` instance to allow for method chaining.
  ///
  /// Example usage:
  /// ```dart
  /// router.group().name("myGroup");
  /// ```
  RouterGroupBuilder name(String groupName) {
    _router.groupName = groupName;
    return this;
  }

  /// Excludes middleware from this group.
  RouterGroupBuilder withoutMiddleware(Iterable<Object> middlewares) {
    _router.excludeMiddlewares(middlewares);
    return this;
  }
}
