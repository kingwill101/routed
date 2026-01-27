library;

import 'dart:io';

import 'package:test/test.dart';

import 'inertia_testing_settings.dart';

/// Provides fluent assertions for Inertia page payloads.
///
/// ```dart
/// response.assertInertia((page) {
///   page.component('Dashboard').has('user.name');
/// });
/// ```
class AssertableInertia {
  /// Creates an assertion helper for an Inertia page payload.
  AssertableInertia(this.page);

  static final Object _notFound = Object();
  static const Object _missing = Object();

  /// Shared testing settings for component checks.
  static final InertiaTestingSettings testing = InertiaTestingSettings();

  /// The raw page payload.
  final Map<String, dynamic> page;

  /// The props map extracted from [page].
  Map<String, dynamic> get props =>
      (page['props'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  /// Asserts the page component matches [expected].
  ///
  /// When [ensurePageExists] is enabled, checks the filesystem for the
  /// component using [pagePaths] and [pageExtensions].
  AssertableInertia component(
    String expected, {
    bool? ensurePageExists,
    List<String>? pagePaths,
    List<String>? pageExtensions,
  }) {
    expect(
      page['component'],
      equals(expected),
      reason: 'Unexpected Inertia page component.',
    );
    final shouldCheck = ensurePageExists ?? testing.ensurePagesExist;
    if (shouldCheck) {
      final paths = pagePaths ?? testing.pagePaths;
      final extensions = pageExtensions ?? testing.pageExtensions;
      if (!_componentExists(expected, paths, extensions)) {
        fail('Inertia page component file [$expected] does not exist.');
      }
    }
    return this;
  }

  /// Asserts the page URL matches [expected].
  AssertableInertia url(String expected) {
    expect(
      page['url'],
      equals(expected),
      reason: 'Unexpected Inertia page url.',
    );
    return this;
  }

  /// Asserts the asset version matches [expected].
  AssertableInertia version(String expected) {
    expect(
      page['version'],
      equals(expected),
      reason: 'Unexpected Inertia asset version.',
    );
    return this;
  }

  /// Asserts the prop at [path] matches [expected].
  AssertableInertia where(String path, dynamic expected) {
    final actual = _getPathValue(props, path);
    expect(actual, equals(expected), reason: 'Unexpected value for $path.');
    return this;
  }

  /// Executes [callback] against a reloaded response.
  ///
  /// When [propsOverride] is provided, it replaces the props for assertions.
  AssertableInertia reload(
    void Function(AssertableInertia inertia) callback, {
    Map<String, dynamic>? propsOverride,
  }) {
    final next = _withProps(propsOverride ?? props);
    callback(AssertableInertia(next));
    return this;
  }

  /// Executes [callback] against a response containing only [keys].
  ///
  /// When [propsOverride] is provided, it replaces the props before filtering.
  AssertableInertia reloadOnly(
    Object keys,
    void Function(AssertableInertia inertia) callback, {
    Map<String, dynamic>? propsOverride,
  }) {
    final resolved = propsOverride ?? props;
    final only = _normalizeKeys(keys);
    final filtered = _filterOnlyProps(resolved, only);
    callback(AssertableInertia(_withProps(filtered)));
    return this;
  }

  /// Executes [callback] against a response excluding [keys].
  ///
  /// When [propsOverride] is provided, it replaces the props before filtering.
  AssertableInertia reloadExcept(
    Object keys,
    void Function(AssertableInertia inertia) callback, {
    Map<String, dynamic>? propsOverride,
  }) {
    final resolved = Map<String, dynamic>.from(propsOverride ?? props);
    final except = _normalizeKeys(keys);
    for (final path in except) {
      _removePath(resolved, path);
    }
    callback(AssertableInertia(_withProps(resolved)));
    return this;
  }

  /// Executes [callback] against the deferred props for [groups].
  ///
  /// When [groups] is omitted, all deferred groups are included. When
  /// [propsOverride] is provided, it supplies the resolved deferred values.
  AssertableInertia loadDeferredProps(
    void Function(AssertableInertia inertia) callback, {
    Object? groups,
    Map<String, dynamic>? propsOverride,
  }) {
    final deferred = _deferredProps();
    final targetGroups = groups == null
        ? deferred.keys.toList()
        : _normalizeKeys(groups);
    final keys = <String>[];
    for (final group in targetGroups) {
      final items = deferred[group];
      if (items != null) {
        keys.addAll(items);
      }
    }
    final resolved = propsOverride ?? props;
    final filtered = _filterOnlyProps(resolved, keys);
    callback(AssertableInertia(_withProps(filtered)));
    return this;
  }

  /// Asserts flash data exists at [path], optionally matching [expected].
  AssertableInertia hasFlash(String path, [Object? expected = _missing]) {
    final actual = _getPathValue(_flashData(), path, allowMissing: true);
    if (actual == null) {
      fail('Inertia Flash Data is missing key [$path].');
    }
    if (!identical(expected, _missing)) {
      expect(
        actual,
        equals(expected),
        reason: 'Inertia Flash Data [$path] does not match expected value.',
      );
    }
    return this;
  }

  /// Asserts flash data is missing at [path].
  AssertableInertia missingFlash(String path) {
    final actual = _getPathValue(_flashData(), path, allowMissing: true);
    if (actual != null) {
      fail('Inertia Flash Data has unexpected key [$path].');
    }
    return this;
  }

  /// Asserts that a prop exists at [path].
  AssertableInertia has(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual != null, isTrue, reason: 'Missing prop $path.');
    return this;
  }

  /// Asserts that a prop is missing at [path].
  AssertableInertia missing(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual == null, isTrue, reason: 'Prop $path should be missing.');
    return this;
  }

  /// Returns the nested value at [path], or fails the test if missing.
  dynamic _getPathValue(
    Map<String, dynamic> data,
    String path, {
    bool allowMissing = false,
  }) {
    dynamic current = data;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        if (allowMissing) return null;
        fail('Path "$path" does not exist in props.');
      }
    }
    return current;
  }

  Map<String, dynamic> _withProps(Map<String, dynamic> nextProps) {
    return {...page, 'props': nextProps};
  }

  Map<String, dynamic> _flashData() {
    final data = page['flash'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const <String, dynamic>{};
  }

  Map<String, List<String>> _deferredProps() {
    final data = page['deferredProps'];
    if (data is Map) {
      final result = <String, List<String>>{};
      data.forEach((key, value) {
        if (value is Iterable) {
          result[key.toString()] = value
              .map((item) => item.toString())
              .toList();
        }
      });
      return result;
    }
    return const <String, List<String>>{};
  }

  List<String> _normalizeKeys(Object keys) {
    if (keys is String) return [keys];
    if (keys is Iterable) {
      return keys.map((item) => item.toString()).toList();
    }
    throw ArgumentError('Keys must be a String or Iterable<String>.');
  }

  Map<String, dynamic> _filterOnlyProps(
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

  dynamic _getPath(Map<String, dynamic> props, String path) {
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

  void _setPath(Map<String, dynamic> target, String path, dynamic value) {
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

  void _removePath(Map<String, dynamic> target, String path) {
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
}

bool _componentExists(
  String component,
  List<String> paths,
  List<String> extensions,
) {
  final normalizedComponent = component.startsWith('/')
      ? component.substring(1)
      : component;
  final resolvedPaths = paths.isEmpty ? [Directory.current.path] : paths;
  final resolvedExtensions = extensions.isEmpty
      ? const ['']
      : List<String>.from(extensions);

  for (final base in resolvedPaths) {
    final directCandidate = _joinPath(base, normalizedComponent);
    if (File(directCandidate).existsSync()) {
      return true;
    }
  }

  for (final base in resolvedPaths) {
    for (final extension in resolvedExtensions) {
      final suffix = extension.isEmpty
          ? ''
          : extension.startsWith('.')
          ? extension
          : '.$extension';
      final candidate = _joinPath(base, '$normalizedComponent$suffix');
      if (File(candidate).existsSync()) {
        return true;
      }
    }
  }

  return false;
}

String _joinPath(String base, String value) {
  if (base.isEmpty) return value;
  if (base.endsWith('/')) return '$base$value';
  return '$base/$value';
}
