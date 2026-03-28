library;

import 'dart:async';

import '../inertia_serializable.dart';
import '../property_context.dart';
import 'always_prop.dart';
import 'inertia_prop.dart';
import 'lazy_prop.dart';
import 'optional_prop.dart';
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

class _ResolutionState {
  _ResolutionState(this.context) : now = DateTime.now();

  final PropertyContext context;
  final DateTime now;
  final Map<String, List<String>> deferredProps = <String, List<String>>{};
  final List<String> mergeProps = <String>[];
  final List<String> deepMergeProps = <String>[];
  final List<String> prependProps = <String>[];
  final List<String> matchPropsOn = <String>[];
  final Map<String, Map<String, dynamic>> scrollProps =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> onceProps =
      <String, Map<String, dynamic>>{};

  PropertyResolutionResult build(Map<String, dynamic> props) {
    return PropertyResolutionResult(
      props: props,
      deferredProps: deferredProps,
      mergeProps: mergeProps,
      deepMergeProps: deepMergeProps,
      prependProps: prependProps,
      matchPropsOn: matchPropsOn,
      scrollProps: scrollProps,
      onceProps: onceProps,
    );
  }
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
  static PropertyResolutionResult resolve(
    Map<String, dynamic> props,
    PropertyContext context,
  ) {
    final state = _ResolutionState(context);
    final normalized = _normalizeRootProps(props);
    final resolved = _resolveMapSync(normalized, state);
    return state.build(resolved);
  }

  /// Resolves [props] asynchronously for the given [context].
  static Future<PropertyResolutionResult> resolveAsync(
    Map<String, dynamic> props,
    PropertyContext context,
  ) async {
    final state = _ResolutionState(context);
    final normalized = _normalizeRootProps(props);
    final resolved = await _resolveMapAsync(normalized, state);
    return state.build(resolved);
  }

  static Map<String, dynamic> _resolveMapSync(
    Map<String, dynamic> props,
    _ResolutionState state, {
    String prefix = '',
    bool parentWasResolved = false,
  }) {
    final resolved = <String, dynamic>{};
    for (final entry in props.entries) {
      final key = entry.key;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = _resolveNodeSync(
        entry.value,
        state,
        path: path,
        parentWasResolved: parentWasResolved,
      );
      if (!identical(value, _notFound)) {
        resolved[key] = value;
      }
    }
    return resolved;
  }

  static Future<Map<String, dynamic>> _resolveMapAsync(
    Map<String, dynamic> props,
    _ResolutionState state, {
    String prefix = '',
    bool parentWasResolved = false,
  }) async {
    final resolved = <String, dynamic>{};
    for (final entry in props.entries) {
      final key = entry.key;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = await _resolveNodeAsync(
        entry.value,
        state,
        path: path,
        parentWasResolved: parentWasResolved,
      );
      if (!identical(value, _notFound)) {
        resolved[key] = value;
      }
    }
    return resolved;
  }

  static dynamic _resolveNodeSync(
    dynamic node,
    _ResolutionState state, {
    required String path,
    required bool parentWasResolved,
  }) {
    if (!_shouldIncludeInPartialResponse(
      node,
      state.context,
      path,
      parentWasResolved,
    )) {
      return _notFound;
    }

    if (node is ScrollProp) {
      node.configureMergeIntent(state.context.mergeIntent);
    }

    if (!state.context.isPartialReload &&
        _excludeFromInitialResponse(node, state, path)) {
      return _notFound;
    }

    var prop = node;
    var resolved = _resolveValueSync(node, state.context, path);

    if (!identical(resolved, prop) && resolved is InertiaProp) {
      prop = resolved;
      if (prop is ScrollProp) {
        prop.configureMergeIntent(state.context.mergeIntent);
      }
      if (!_shouldIncludeInPartialResponse(
        prop,
        state.context,
        path,
        parentWasResolved,
      )) {
        return _notFound;
      }
      if (!state.context.isPartialReload &&
          _excludeFromInitialResponse(prop, state, path)) {
        return _notFound;
      }
      resolved = _resolveValueSync(prop, state.context, path);
    }

    _collectIncludedMetadataSync(prop, state, path);

    if (resolved is Map) {
      final mapped = _coerceMap(resolved);
      if (mapped.isEmpty) return mapped;
      final nested = _resolveMapSync(
        mapped,
        state,
        prefix: path,
        parentWasResolved: parentWasResolved || !_isStructuredValue(prop),
      );
      return nested.isEmpty ? _notFound : nested;
    }

    if (_isIterableValue(resolved)) {
      return _resolveListSync(
        resolved as Iterable,
        state,
        prefix: path,
        parentWasResolved: parentWasResolved || !_isStructuredValue(prop),
      );
    }

    return resolved;
  }

  static Future<dynamic> _resolveNodeAsync(
    dynamic node,
    _ResolutionState state, {
    required String path,
    required bool parentWasResolved,
  }) async {
    if (!_shouldIncludeInPartialResponse(
      node,
      state.context,
      path,
      parentWasResolved,
    )) {
      return _notFound;
    }

    if (node is ScrollProp) {
      node.configureMergeIntent(state.context.mergeIntent);
    }

    if (!state.context.isPartialReload &&
        _excludeFromInitialResponse(node, state, path)) {
      return _notFound;
    }

    var prop = node;
    var resolved = await _resolveValueAsync(node, state.context, path);

    if (!identical(resolved, prop) && resolved is InertiaProp) {
      prop = resolved;
      if (prop is ScrollProp) {
        prop.configureMergeIntent(state.context.mergeIntent);
      }
      if (!_shouldIncludeInPartialResponse(
        prop,
        state.context,
        path,
        parentWasResolved,
      )) {
        return _notFound;
      }
      if (!state.context.isPartialReload &&
          _excludeFromInitialResponse(prop, state, path)) {
        return _notFound;
      }
      resolved = await _resolveValueAsync(prop, state.context, path);
    }

    await _collectIncludedMetadataAsync(prop, state, path);

    if (resolved is Map) {
      final mapped = _coerceMap(resolved);
      if (mapped.isEmpty) return mapped;
      final nested = await _resolveMapAsync(
        mapped,
        state,
        prefix: path,
        parentWasResolved: parentWasResolved || !_isStructuredValue(prop),
      );
      return nested.isEmpty ? _notFound : nested;
    }

    if (_isIterableValue(resolved)) {
      return _resolveListAsync(
        resolved as Iterable,
        state,
        prefix: path,
        parentWasResolved: parentWasResolved || !_isStructuredValue(prop),
      );
    }

    return resolved;
  }

  static List<dynamic> _resolveListSync(
    Iterable values,
    _ResolutionState state, {
    required String prefix,
    required bool parentWasResolved,
  }) {
    final resolved = <dynamic>[];
    var index = 0;
    for (final value in values) {
      final item = _resolveNodeSync(
        value,
        state,
        path: '$prefix.$index',
        parentWasResolved: true,
      );
      if (!identical(item, _notFound)) {
        resolved.add(item);
      }
      index++;
    }
    return resolved;
  }

  static Future<List<dynamic>> _resolveListAsync(
    Iterable values,
    _ResolutionState state, {
    required String prefix,
    required bool parentWasResolved,
  }) async {
    final resolved = <dynamic>[];
    var index = 0;
    for (final value in values) {
      final item = await _resolveNodeAsync(
        value,
        state,
        path: '$prefix.$index',
        parentWasResolved: true,
      );
      if (!identical(item, _notFound)) {
        resolved.add(item);
      }
      index++;
    }
    return resolved;
  }

  static bool _excludeFromInitialResponse(
    dynamic prop,
    _ResolutionState state,
    String path,
  ) {
    if (prop is LazyProp || prop is OptionalProp) {
      if (prop is OnceableProp && prop.shouldResolveOnce) {
        _recordOnceMetadata(path, prop, state);
      }
      return true;
    }

    if (_shouldExcludeLoadedOnce(prop, state.context, path)) {
      if (prop is OnceableProp) {
        _recordOnceMetadata(path, prop, state);
      }
      return true;
    }

    if (prop is DeferrableProp && prop.shouldDefer) {
      _recordDeferredMetadata(path, prop, state);
      final MergeableProp? mergeable = prop is MergeableProp
          ? prop as MergeableProp
          : null;
      if (mergeable != null && mergeable.shouldMerge) {
        _recordMergeMetadata(path, mergeable, state);
      }
      final OnceableProp? onceable = prop is OnceableProp
          ? prop as OnceableProp
          : null;
      if (onceable != null && onceable.shouldResolveOnce) {
        _recordOnceMetadata(path, onceable, state);
      }
      return true;
    }

    return false;
  }

  static bool _shouldExcludeLoadedOnce(
    dynamic prop,
    PropertyContext context,
    String path,
  ) {
    if (!context.isInertiaRequest || context.isPartialReload) return false;
    if (prop is! OnceableProp || !prop.shouldResolveOnce) return false;
    if (prop.shouldRefresh) return false;
    final onceKey = prop.onceKey ?? path;
    return context.exceptOnceProps.contains(onceKey);
  }

  static void _collectIncludedMetadataSync(
    dynamic prop,
    _ResolutionState state,
    String path,
  ) {
    if (prop is MergeableProp && prop.shouldMerge) {
      _recordMergeMetadata(path, prop, state);
    }

    if (prop is ScrollProp) {
      _recordScrollMetadataSync(path, prop, state);
    }

    if (prop is OnceableProp && prop.shouldResolveOnce) {
      _recordOnceMetadata(path, prop, state);
    }
  }

  static Future<void> _collectIncludedMetadataAsync(
    dynamic prop,
    _ResolutionState state,
    String path,
  ) async {
    if (prop is MergeableProp && prop.shouldMerge) {
      _recordMergeMetadata(path, prop, state);
    }

    if (prop is ScrollProp) {
      await _recordScrollMetadataAsync(path, prop, state);
    }

    if (prop is OnceableProp && prop.shouldResolveOnce) {
      _recordOnceMetadata(path, prop, state);
    }
  }

  static void _recordDeferredMetadata(
    String path,
    DeferrableProp prop,
    _ResolutionState state,
  ) {
    state.deferredProps.putIfAbsent(prop.group, () => <String>[]).add(path);
  }

  static void _recordMergeMetadata(
    String path,
    MergeableProp prop,
    _ResolutionState state,
  ) {
    if (state.context.resetKeys.contains(path)) {
      return;
    }

    if (state.context.isPartialReload &&
        !_isIncludedInPartialMetadata(path, state.context)) {
      return;
    }

    if (prop.shouldDeepMerge) {
      state.deepMergeProps.add(path);
    } else {
      if (prop.appendsAtRoot) {
        state.mergeProps.add(path);
      }
      for (final appendPath in prop.appendsAtPaths) {
        state.mergeProps.add('$path.$appendPath');
      }
      if (prop.prependsAtRoot) {
        state.prependProps.add(path);
      }
      for (final prependPath in prop.prependsAtPaths) {
        state.prependProps.add('$path.$prependPath');
      }
    }

    for (final matchOn in prop.matchesOn) {
      state.matchPropsOn.add('$path.$matchOn');
    }
  }

  static void _recordScrollMetadataSync(
    String path,
    ScrollProp prop,
    _ResolutionState state,
  ) {
    if (state.context.isPartialReload &&
        !_isIncludedInPartialMetadata(path, state.context)) {
      return;
    }

    state.scrollProps[path] = {
      ...prop.metadata().toJson(),
      'reset': state.context.resetKeys.contains(path),
    };
  }

  static Future<void> _recordScrollMetadataAsync(
    String path,
    ScrollProp prop,
    _ResolutionState state,
  ) async {
    if (state.context.isPartialReload &&
        !_isIncludedInPartialMetadata(path, state.context)) {
      return;
    }

    final metadata = await prop.metadataAsync();
    state.scrollProps[path] = {
      ...metadata.toJson(),
      'reset': state.context.resetKeys.contains(path),
    };
  }

  static void _recordOnceMetadata(
    String path,
    OnceableProp prop,
    _ResolutionState state,
  ) {
    if (state.context.isPartialReload &&
        !_isIncludedInPartialMetadata(path, state.context)) {
      return;
    }

    final onceKey = prop.onceKey ?? path;
    final expiresAt = prop.ttl == null
        ? null
        : state.now.add(prop.ttl!).millisecondsSinceEpoch;
    state.onceProps[onceKey] = {
      'prop': path,
      if (expiresAt != null) 'expiresAt': expiresAt,
    };
  }

  static bool _shouldIncludeInPartialResponse(
    dynamic node,
    PropertyContext context,
    String path,
    bool parentWasResolved,
  ) {
    if (!context.isPartialReload || parentWasResolved || node is AlwaysProp) {
      return true;
    }
    return _pathMatchesPartialRequest(path, context);
  }

  static bool _pathMatchesPartialRequest(String path, PropertyContext context) {
    if (context.requestedProps.isNotEmpty &&
        !_matchesOnly(path, context.requestedProps) &&
        !_leadsToOnly(path, context.requestedProps)) {
      return false;
    }

    if (_matchesExcept(path, context.requestedExceptProps)) {
      return false;
    }

    return true;
  }

  static bool _isIncludedInPartialMetadata(
    String path,
    PropertyContext context,
  ) {
    if (context.requestedProps.isNotEmpty &&
        !_matchesOnly(path, context.requestedProps)) {
      return false;
    }

    if (_matchesExcept(path, context.requestedExceptProps)) {
      return false;
    }

    return true;
  }

  static bool _matchesOnly(String path, List<String> requestedProps) {
    return requestedProps.any(
      (item) => item == path || path.startsWith('$item.'),
    );
  }

  static bool _leadsToOnly(String path, List<String> requestedProps) {
    return requestedProps.any((item) => item.startsWith('$path.'));
  }

  static bool _matchesExcept(String path, List<String> requestedExceptProps) {
    return requestedExceptProps.any(
      (item) => item == path || path.startsWith('$item.'),
    );
  }

  static dynamic _resolveValueSync(
    dynamic value,
    PropertyContext context,
    String path,
  ) {
    if (value is InertiaProp) {
      return value.resolve(path, context);
    }

    var current = value;
    while (true) {
      if (current is InertiaSerializable) {
        current = current.toInertia();
        continue;
      }
      if (current is Function) {
        current = current();
        continue;
      }
      break;
    }
    return current;
  }

  static Future<dynamic> _resolveValueAsync(
    dynamic value,
    PropertyContext context,
    String path,
  ) async {
    dynamic current = value is InertiaProp
        ? value.resolve(path, context)
        : value;
    while (true) {
      if (current is Future) {
        current = await current;
        continue;
      }
      if (current is InertiaSerializable) {
        current = current.toInertia();
        continue;
      }
      if (current is Function) {
        current = current();
        continue;
      }
      break;
    }
    return current;
  }

  static Map<String, dynamic> _normalizeRootProps(Map<String, dynamic> props) {
    return _unpackTopLevelDotProps(_coerceMap(props));
  }

  static Map<String, dynamic> _coerceMap(Map map) {
    final coerced = <String, dynamic>{};
    for (final entry in map.entries) {
      coerced[entry.key.toString()] = entry.value;
    }
    return coerced;
  }

  static bool _isStructuredValue(dynamic value) {
    return value is Map || _isIterableValue(value);
  }

  static bool _isIterableValue(dynamic value) {
    return value is Iterable && value is! String;
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
}
