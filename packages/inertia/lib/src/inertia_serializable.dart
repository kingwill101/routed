/// Defines an object that can serialize itself for Inertia props.
///
/// ```dart
/// class User implements InertiaSerializable {
///   User(this.name);
///   final String name;
///
///   @override
///   Map<String, dynamic> toInertia() => {'name': name};
/// }
/// ```
abstract class InertiaSerializable {
  /// Returns a JSON-serializable map for use in Inertia props.
  Map<String, dynamic> toInertia();
}
