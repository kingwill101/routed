import '../property_context.dart';
import 'inertia_prop.dart';

/// Property that captures scroll metadata
class ScrollProp<T> implements InertiaProp {
  ScrollProp(this.resolver);
  final T Function() resolver;

  @override
  bool shouldInclude(String key, PropertyContext context) => true;

  @override
  T resolve(String key, PropertyContext context) => resolver();
}
