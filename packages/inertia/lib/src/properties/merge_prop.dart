import '../property_context.dart';
import 'inertia_prop.dart';

/// Property that indicates its value should be merged with existing props
class MergeProp<T> implements InertiaProp {
  MergeProp(this.resolver, {this.deepMerge = false});
  final T Function() resolver;
  final bool deepMerge;

  @override
  bool shouldInclude(String key, PropertyContext context) {
    if (!context.isPartialReload) return true;
    if (context.requestedProps.isEmpty) return true;
    return context.requestedProps.contains(key);
  }

  @override
  T resolve(String key, PropertyContext context) {
    if (shouldInclude(key, context)) {
      return resolver();
    }

    throw Exception('Merge property accessed without being requested');
  }
}
