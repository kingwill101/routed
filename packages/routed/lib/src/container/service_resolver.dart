import 'dart:async';

/// Narrow read-only view for feature packages.
///
/// Prefer this over [Container] in library code that only needs lookup
/// without mutation, per refactor.md §6.2.
abstract interface class ServiceResolver {
  /// Returns `true` if a binding for [T] exists.
  bool has<T>();

  /// Synchronously gets an already-resolved instance of [T].
  ///
  /// Throws [StateError] if no sync instance is available.
  T get<T>();

  /// Asynchronously resolves or creates an instance of [T].
  Future<T> make<T>();
}
