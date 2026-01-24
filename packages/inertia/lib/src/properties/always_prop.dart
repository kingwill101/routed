import '../property_context.dart';
import 'inertia_prop.dart';

/// Always property that is included in every response
class AlwaysProp<T> implements InertiaProp {
  AlwaysProp(this.resolver);
  final T Function() resolver;
  T? _resolvedValue;

  @override
  bool shouldInclude(String key, PropertyContext context) => true;

  @override
  T resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    if (_resolvedValue != null) return _resolvedValue!;

    _resolvedValue = resolver();
    return _resolvedValue!;
  }
}
