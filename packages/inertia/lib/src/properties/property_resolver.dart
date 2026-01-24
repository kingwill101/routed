import '../property_context.dart';
import '../inertia_serializable.dart';
import 'deferred_prop.dart';
import 'inertia_prop.dart';
import 'merge_prop.dart';

/// Result of resolving Inertia props
class PropertyResolutionResult {
  const PropertyResolutionResult({
    required this.props,
    required this.deferredProps,
    required this.mergeProps,
  });
  final Map<String, dynamic> props;
  final Map<String, List<String>> deferredProps;
  final List<String> mergeProps;
}

/// Resolves Inertia props based on context and prop types
class PropertyResolver {
  static PropertyResolutionResult resolve(
    Map<String, dynamic> props,
    PropertyContext context,
  ) {
    final resolvedProps = <String, dynamic>{};
    final deferredProps = <String, List<String>>{};
    final mergeProps = <String>[];

    props.forEach((key, value) {
      if (!context.shouldIncludeProp(key)) {
        return;
      }

      if (value is InertiaProp) {
        if (value is DeferredProp) {
          final group = value.group;
          if (value.shouldInclude(key, context)) {
            resolvedProps[key] = value.resolve(key, context);
            if (value.shouldMerge && !context.resetKeys.contains(key)) {
              mergeProps.add(key);
            }
          } else {
            deferredProps.putIfAbsent(group, () => []).add(key);
          }
          return;
        }

        if (!value.shouldInclude(key, context)) {
          return;
        }

        resolvedProps[key] = value.resolve(key, context);

        if (value is MergeProp && !context.resetKeys.contains(key)) {
          mergeProps.add(key);
        }
        return;
      }

      resolvedProps[key] = value;
    });

    final resolvedWithCallables =
        _deepResolveCallables(resolvedProps) as Map<String, dynamic>;

    return PropertyResolutionResult(
      props: resolvedWithCallables,
      deferredProps: deferredProps,
      mergeProps: mergeProps,
    );
  }

  static dynamic _deepResolveCallables(dynamic value) {
    if (value is InertiaSerializable) {
      return _deepResolveCallables(value.toInertia());
    }

    if (value is Map) {
      final resolved = <String, dynamic>{};
      value.forEach((key, item) {
        resolved[key.toString()] = _deepResolveCallables(item);
      });
      return resolved;
    }

    if (value is Iterable) {
      return value.map(_deepResolveCallables).toList();
    }

    if (value is Function) {
      return _deepResolveCallables(value());
    }

    return value;
  }
}
