import '../property_context.dart';
import 'inertia_prop.dart';

/// Lazy property that is only resolved when explicitly requested
class LazyProp<T> implements InertiaProp {
  LazyProp(this.resolver);
  final T Function() resolver;
  T? _cachedValue;

  @override
  bool shouldInclude(String key, PropertyContext context) {
    // Only include in partial reloads if explicitly requested
    if (!context.isPartialReload) return true;
    return context.requestedProps.contains(key);
  }

  @override
  T resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    if (_cachedValue != null) return _cachedValue!;

    if (shouldInclude(key, context)) {
      _cachedValue = resolver();
      return _cachedValue!;
    }

    throw Exception('Lazy property accessed without being requested');
  }
}
