/// Typed key for request-scoped context state.
///
/// Prefer typed keys over raw string keys to avoid collisions
/// between independent packages (e.g. two packages using "user").
///
/// Example:
/// ```dart
/// const authenticatedUserKey = ContextKey<AuthenticatedUser>('routed.auth.user');
/// ctx.write(authenticatedUserKey, user);
/// final user = ctx.read(authenticatedUserKey);
/// ```
final class ContextKey<T> {
  /// Creates a typed key with the namespaced [name].
  const ContextKey(this.name);

  /// Namespaced key name, e.g. 'routed.auth.user'.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ContextKey<T> && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ContextKey<$T>($name)';
}
