import '../property_context.dart';
import 'inertia_prop.dart';

/// Optional property that is included on first load but only resolved on partial reloads
class OptionalProp<T> implements InertiaProp {
  OptionalProp(this.resolver);
  final T Function() resolver;
  T? _resolvedValue;

  @override
  bool shouldInclude(String key, PropertyContext context) {
    if (!context.isPartialReload) return false;

    return context.requestedProps.contains(key);
  }

  @override
  T resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    if (_resolvedValue != null) return _resolvedValue!;

    // Only resolve on partial reloads if requested
    if (!shouldInclude(key, context)) {
      throw Exception('Optional property accessed without being requested');
    }

    _resolvedValue = resolver();
    return _resolvedValue!;
  }
}
