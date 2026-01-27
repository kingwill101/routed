library;

import 'dart:async';

import '../property_context.dart';
import '../inertia_serializable.dart';
import 'always_prop.dart';
import 'inertia_prop.dart';
import 'scroll_prop.dart';

/// Result of resolving Inertia props and merge metadata.
class PropertyResolutionResult {
  /// Creates a resolution result with resolved values and metadata.
  const PropertyResolutionResult({
    required this.props,
    required this.deferredProps,
    required this.mergeProps,
    required this.deepMergeProps,
    required this.prependProps,
    required this.matchPropsOn,
    required this.scrollProps,
    required this.onceProps,
  });

  /// The resolved props ready for JSON serialization.
  final Map<String, dynamic> props;

  /// Deferred props grouped by deferred group name.
  final Map<String, List<String>> deferredProps;

  /// Prop keys to merge shallowly on the client.
  final List<String> mergeProps;

  /// Prop keys to merge deeply on the client.
  final List<String> deepMergeProps;

  /// Prop keys to prepend on merge.
  final List<String> prependProps;

  /// Prop keys to match on during merge.
  final List<String> matchPropsOn;

  /// Scroll prop metadata keyed by prop name.
  final Map<String, Map<String, dynamic>> scrollProps;

  /// Once prop metadata keyed by once key.
  final Map<String, Map<String, dynamic>> onceProps;
}

/// Resolves Inertia props into payload data and merge metadata.
///
/// ```dart
/// final result = PropertyResolver.resolve(props, context);
/// final payload = result.props;
/// ```
class PropertyResolver {
  static final Object _notFound = Object();

  /// Resolves [props] for the given [context] and returns merge metadata.
  ///
  /// ```dart
  /// final result = PropertyResolver.resolve(
  ///   {'user': user, 'stats': LazyProp(() => loadStats())},
  ///   context,
  /// );
  /// ```
  static PropertyResolutionResult resolve(
    Map<String, dynamic> props,
    PropertyContext context,
  ) {
    final resolvedProps = <String, dynamic>{};
    final deferredProps = <String, List<String>>{};
    final mergeProps = <String>[];
    final deepMergeProps = <String>[];
    final prependProps = <String>[];
    final matchPropsOn = <String>[];
    final scrollProps = <String, Map<String, dynamic>>{};
    final onceProps = <String, Map<String, dynamic>>{};

    final alwaysProps = _extractAlwaysProps(props);
    final filteredProps = _applyPartialFilters(props, context);
    final workingProps = <String, dynamic>{...alwaysProps, ...filteredProps};

    final now = DateTime.now();
    final shouldApplyOnceExclusions =
        context.isInertiaRequest && !context.isPartialReload;

    for (final entry in workingProps.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is ScrollProp) {
        value.configureMergeIntent(context.mergeIntent);
      }

      if (value is OnceableProp && value.shouldResolveOnce) {
        final onceKey = value.onceKey ?? key;
        final expiresAt = value.ttl == null
            ? null
            : now.add(value.ttl!).millisecondsSinceEpoch;
        onceProps[onceKey] = {'prop': key, 'expiresAt': expiresAt};
      }

      if (value is MergeableProp && value.shouldMerge) {
        if (!context.resetKeys.contains(key)) {
          if (value.shouldDeepMerge) {
            deepMergeProps.add(key);
          } else {
            if (value.appendsAtRoot) {
              mergeProps.add(key);
            }
            for (final path in value.appendsAtPaths) {
              mergeProps.add('$key.$path');
            }
            if (value.prependsAtRoot) {
              prependProps.add(key);
            }
            for (final path in value.prependsAtPaths) {
              prependProps.add('$key.$path');
            }
          }
          for (final matchOn in value.matchesOn) {
            matchPropsOn.add('$key.$matchOn');
          }
        }

        if (value is ScrollProp) {
          final shouldSkip = !context.isPartialReload && value.shouldDefer;
          if (!shouldSkip) {
            scrollProps[key] = {
              ...value.metadata().toJson(),
              'reset': context.resetKeys.contains(key),
            };
          }
        }
      }
    }

    for (final entry in workingProps.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is InertiaProp) {
        final deferrable = value is DeferrableProp
            ? value as DeferrableProp
            : null;
        final onceable = value is OnceableProp ? value as OnceableProp : null;

        if (deferrable != null && deferrable.shouldDefer) {
          if (!context.isPartialReload) {
            if (!(shouldApplyOnceExclusions &&
                onceable != null &&
                _shouldExcludeOnce(context, onceable, key))) {
              deferredProps.putIfAbsent(deferrable.group, () => []).add(key);
            }
            continue;
          }
        }

        if (shouldApplyOnceExclusions &&
            onceable != null &&
            _shouldExcludeOnce(context, onceable, key)) {
          continue;
        }

        if (!value.shouldInclude(key, context)) {
          continue;
        }

        resolvedProps[key] = value.resolve(key, context);
        continue;
      }

      resolvedProps[key] = value;
    }

    final resolvedWithCallables =
        _deepResolveCallables(resolvedProps) as Map<String, dynamic>;
    final unpacked = _unpackTopLevelDotProps(resolvedWithCallables);

    return PropertyResolutionResult(
      props: unpacked,
      deferredProps: deferredProps,
      mergeProps: mergeProps,
      deepMergeProps: deepMergeProps,
      prependProps: prependProps,
      matchPropsOn: matchPropsOn,
      scrollProps: scrollProps,
      onceProps: onceProps,
    );
  }

  /// Resolves [props] asynchronously for the given [context].
  static Future<PropertyResolutionResult> resolveAsync(
    Map<String, dynamic> props,
    PropertyContext context,
  ) async {
    final resolvedProps = <String, dynamic>{};
    final deferredProps = <String, List<String>>{};
    final mergeProps = <String>[];
    final deepMergeProps = <String>[];
    final prependProps = <String>[];
    final matchPropsOn = <String>[];
    final scrollProps = <String, Map<String, dynamic>>{};
    final onceProps = <String, Map<String, dynamic>>{};

    final alwaysProps = _extractAlwaysProps(props);
    final filteredProps = _applyPartialFilters(props, context);
    final workingProps = <String, dynamic>{...alwaysProps, ...filteredProps};

    final now = DateTime.now();
    final shouldApplyOnceExclusions =
        context.isInertiaRequest && !context.isPartialReload;

    for (final entry in workingProps.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is ScrollProp) {
        value.configureMergeIntent(context.mergeIntent);
      }

      if (value is OnceableProp && value.shouldResolveOnce) {
        final onceKey = value.onceKey ?? key;
        final expiresAt = value.ttl == null
            ? null
            : now.add(value.ttl!).millisecondsSinceEpoch;
        onceProps[onceKey] = {'prop': key, 'expiresAt': expiresAt};
      }

      if (value is MergeableProp && value.shouldMerge) {
        if (!context.resetKeys.contains(key)) {
          if (value.shouldDeepMerge) {
            deepMergeProps.add(key);
          } else {
            if (value.appendsAtRoot) {
              mergeProps.add(key);
            }
            for (final path in value.appendsAtPaths) {
              mergeProps.add('$key.$path');
            }
            if (value.prependsAtRoot) {
              prependProps.add(key);
            }
            for (final path in value.prependsAtPaths) {
              prependProps.add('$key.$path');
            }
          }
          for (final matchOn in value.matchesOn) {
            matchPropsOn.add('$key.$matchOn');
          }
        }

        if (value is ScrollProp) {
          final shouldSkip = !context.isPartialReload && value.shouldDefer;
          if (!shouldSkip) {
            final metadata = await value.metadataAsync();
            scrollProps[key] = {
              ...metadata.toJson(),
              'reset': context.resetKeys.contains(key),
            };
          }
        }
      }
    }

    for (final entry in workingProps.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is InertiaProp) {
        final deferrable = value is DeferrableProp
            ? value as DeferrableProp
            : null;
        final onceable = value is OnceableProp ? value as OnceableProp : null;

        if (deferrable != null && deferrable.shouldDefer) {
          if (!context.isPartialReload) {
            if (!(shouldApplyOnceExclusions &&
                onceable != null &&
                _shouldExcludeOnce(context, onceable, key))) {
              deferredProps.putIfAbsent(deferrable.group, () => []).add(key);
            }
            continue;
          }
        }

        if (shouldApplyOnceExclusions &&
            onceable != null &&
            _shouldExcludeOnce(context, onceable, key)) {
          continue;
        }

        if (!value.shouldInclude(key, context)) {
          continue;
        }

        resolvedProps[key] = value.resolve(key, context);
        continue;
      }

      resolvedProps[key] = value;
    }

    final resolvedWithCallables =
        await _deepResolveCallablesAsync(resolvedProps) as Map<String, dynamic>;
    final unpacked = _unpackTopLevelDotProps(resolvedWithCallables);

    return PropertyResolutionResult(
      props: unpacked,
      deferredProps: deferredProps,
      mergeProps: mergeProps,
      deepMergeProps: deepMergeProps,
      prependProps: prependProps,
      matchPropsOn: matchPropsOn,
      scrollProps: scrollProps,
      onceProps: onceProps,
    );
  }

  /// Extracts [AlwaysProp] instances to include in all responses.
  static Map<String, dynamic> _extractAlwaysProps(Map<String, dynamic> props) {
    final alwaysProps = <String, dynamic>{};
    props.forEach((key, value) {
      if (value is AlwaysProp) {
        alwaysProps[key] = value;
      }
    });
    return alwaysProps;
  }

  /// Applies partial reload filters based on [context].
  static Map<String, dynamic> _applyPartialFilters(
    Map<String, dynamic> props,
    PropertyContext context,
  ) {
    if (!context.isPartialReload) {
      return Map<String, dynamic>.from(props);
    }

    var filtered = Map<String, dynamic>.from(props);
    if (context.requestedProps.isNotEmpty) {
      filtered = _filterOnlyProps(filtered, context.requestedProps);
    }
    if (context.requestedExceptProps.isNotEmpty) {
      for (final path in context.requestedExceptProps) {
        _removePath(filtered, path);
      }
    }
    return filtered;
  }

  /// Filters [props] down to the requested prop paths.
  static Map<String, dynamic> _filterOnlyProps(
    Map<String, dynamic> props,
    List<String> requestedProps,
  ) {
    final filtered = <String, dynamic>{};
    for (final path in requestedProps) {
      final value = _getPath(props, path);
      if (!identical(value, _notFound)) {
        _setPath(filtered, path, value);
      }
    }
    return filtered;
  }

  /// Reads a dotted [path] from a nested map.
  static dynamic _getPath(Map<String, dynamic> props, String path) {
    final segments = path.split('.');
    dynamic current = props;
    for (final segment in segments) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return _notFound;
      }
    }
    return current;
  }

  /// Writes a dotted [path] into a nested map, creating nodes as needed.
  static void _setPath(
    Map<String, dynamic> target,
    String path,
    dynamic value,
  ) {
    final segments = path.split('.');
    var current = target;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (i == segments.length - 1) {
        current[segment] = value;
        return;
      }
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
      } else {
        final created = <String, dynamic>{};
        current[segment] = created;
        current = created;
      }
    }
  }

  /// Removes a dotted [path] from a nested map, if present.
  static void _removePath(Map<String, dynamic> target, String path) {
    final segments = path.split('.');
    Map<String, dynamic> current = target;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (!current.containsKey(segment)) {
        return;
      }
      if (i == segments.length - 1) {
        current.remove(segment);
        return;
      }
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
      } else {
        return;
      }
    }
  }

  /// Returns `true` when a once prop should be excluded for [context].
  static bool _shouldExcludeOnce(
    PropertyContext context,
    OnceableProp prop,
    String key,
  ) {
    if (!prop.shouldResolveOnce) return false;
    if (prop.shouldRefresh) return false;
    final onceKey = prop.onceKey ?? key;
    return context.exceptOnceProps.contains(onceKey);
  }

  /// Resolves nested callables and serializable objects to plain data.
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

  /// Resolves nested callables, futures, and serializable objects to plain data.
  static Future<dynamic> _deepResolveCallablesAsync(dynamic value) async {
    if (value is Future) {
      final resolved = await value;
      return _deepResolveCallablesAsync(resolved);
    }

    if (value is InertiaSerializable) {
      return _deepResolveCallablesAsync(value.toInertia());
    }

    if (value is Map) {
      final resolved = <String, dynamic>{};
      for (final entry in value.entries) {
        resolved[entry.key.toString()] = await _deepResolveCallablesAsync(
          entry.value,
        );
      }
      return resolved;
    }

    if (value is Iterable) {
      final items = <dynamic>[];
      for (final item in value) {
        items.add(await _deepResolveCallablesAsync(item));
      }
      return items;
    }

    if (value is Function) {
      final resolved = value();
      return _deepResolveCallablesAsync(resolved);
    }

    return value;
  }

  static Map<String, dynamic> _unpackTopLevelDotProps(
    Map<String, dynamic> props,
  ) {
    final unpacked = <String, dynamic>{};
    for (final entry in props.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key.contains('.')) {
        _setPath(unpacked, key, value);
      } else {
        unpacked[key] = value;
      }
    }
    return unpacked;
  }
}
