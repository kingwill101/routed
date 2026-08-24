import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/context/context_key.dart';

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
    final raw = request.getAttribute<Object?>(key.name);
    if (raw == null) {
      // A written null is only valid for a nullable [T].
      if (null is T) return null as T;
      throw StateError(
        'Key ${key.name} holds null, which is not compatible with $T',
      );
    }
    if (raw is T) return raw as T;
    throw StateError('Key ${key.name} holds ${raw.runtimeType}, not $T');
  }

  /// Writes [value] for [key].
  void write<T>(ContextKey<T> key, T value) => set(key.name, value);

  /// Returns `true` if [key] was written to this context, even when its
  /// value is `null`.
  bool contains<T>(ContextKey<T> key) => hasAttribute(key.name);
}
