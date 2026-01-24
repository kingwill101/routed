import '../property_context.dart';
import 'inertia_prop.dart';

/// Deferred property that is loaded asynchronously after initial page load
class DeferredProp<T> implements InertiaProp {
  DeferredProp(
    this.resolver, {
    String group = 'default',
    bool shouldMerge = false,
  }) : _group = group,
       _shouldMerge = shouldMerge;
  final T Function() resolver;
  final String _group;
  final bool _shouldMerge;

  /// Get the deferred group name
  String get group => _group;

  /// Whether this property should merge with existing props
  bool get shouldMerge => _shouldMerge;

  @override
  bool shouldInclude(String key, PropertyContext context) {
    // Only include if this group is requested
    return context.requestedDeferredGroups.contains(_group);
  }

  @override
  T resolve(String key, PropertyContext context) {
    if (shouldInclude(key, context)) {
      return resolver();
    }

    throw Exception('Deferred property accessed without being requested');
  }
}
