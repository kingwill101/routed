import 'context.dart';
import 'context_key.dart';

/// Typed accessors for [EngineContext] request-scoped state.
///
/// String-based [EngineContext.get]/[set] remains for compatibility;
/// new framework features should use typed keys.
extension TypedContextState on EngineContext {
  /// Reads value for [key] or `null` if absent or type-mismatch.
  T? read<T>(ContextKey<T> key) => get<T>(key.name);

  /// Reads value for [key] or throws [StateError] if absent.
  T require<T>(ContextKey<T> key) => mustGet<T>(key.name);

  /// Writes [value] for [key].
  void write<T>(ContextKey<T> key, T value) => set(key.name, value);

  /// Returns `true` if [key] is present and matches [T].
  bool contains<T>(ContextKey<T> key) => get<T>(key.name) != null;
}
