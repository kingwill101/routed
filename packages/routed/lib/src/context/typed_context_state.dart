import 'context.dart';
import 'context_key.dart';

/// Typed accessors for [EngineContext] request-scoped state.
///
/// String-based [EngineContext.get]/[set] remains for compatibility;
/// new framework features should use typed keys.
extension TypedContextState on EngineContext {
  /// Reads value for [key] or `null` if absent or type-mismatch.
  T? read<T>(ContextKey<T> key) => get<T>(key.name);

  /// Reads value for [key] or throws [StateError] if [key] was never written.
  ///
  /// A value explicitly written as `null` (for a nullable [T]) is considered
  /// present and is returned as `null`.
  T require<T>(ContextKey<T> key) {
    if (!hasAttribute(key.name)) {
      throw StateError('Key ${key.name} not found in context');
    }
    return get<T>(key.name) as T;
  }

  /// Writes [value] for [key].
  void write<T>(ContextKey<T> key, T value) => set(key.name, value);

  /// Returns `true` if [key] was written to this context, even when its
  /// value is `null`.
  bool contains<T>(ContextKey<T> key) => hasAttribute(key.name);
}
