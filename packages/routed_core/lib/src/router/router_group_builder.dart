import 'package:routed_core/src/router/router.dart';

/// Builds and configures a group of routes within a router.
///
/// This class is returned by `router.group(...)`, allowing chained group
/// configuration such as `.name("myGroup").`
class RouterGroupBuilder {
  /// Constructs a `RouterGroupBuilder` with the given router instance.
  ///
  /// The `router` parameter is the router instance that this group will be
  /// associated with.
  RouterGroupBuilder(this._router);

  /// A reference to the router instance that this group belongs to.
  final Router _router;

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
}
